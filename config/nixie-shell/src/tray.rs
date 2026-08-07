use futures::StreamExt;
use gtk::gdk::{self, ffi::gdk_cairo_surface_create_from_pixbuf};
use gtk::prelude::*;
use gtk::{cairo::Surface, glib};
use std::collections::HashMap;
use std::rc::Rc;

struct Session {
    watcher: notifier_host::proxy::StatusNotifierWatcherProxy<'static>,
}

async fn session() -> zbus::Result<&'static Session> {
    static STATE: tokio::sync::OnceCell<Session> = tokio::sync::OnceCell::const_new();
    STATE
        .get_or_try_init(|| async {
            let connection = zbus::Connection::session().await?;
            notifier_host::Watcher::new().attach_to(&connection).await?;
            let (_, watcher) = notifier_host::register_as_host(&connection).await?;
            Ok(Session { watcher })
        })
        .await
}

struct TrayHost {
    container: gtk::Box,
    items: HashMap<String, TrayItem>,
    blacklist: Rc<Vec<String>>,
    pinned: Rc<Vec<String>>,
}

pub fn start(container: &gtk::Box, blacklist: Vec<String>, pinned: Vec<String>) {
    let mut tray = TrayHost {
        container: container.clone(),
        items: HashMap::new(),
        blacklist: Rc::new(blacklist.into_iter().map(|x| x.to_lowercase()).collect()),
        pinned: Rc::new(pinned.into_iter().map(|x| x.to_lowercase()).collect()),
    };
    let task = glib::MainContext::default().spawn_local(async move {
        match session().await {
            Ok(s) => {
                let error = notifier_host::run_host(&mut tray, &s.watcher).await;
                log::error!("tray host stopped: {error}");
            }
            Err(error) => log::error!("tray initialization failed: {error}"),
        }
    });
    container.connect_destroy(move |_| task.abort());
}

impl notifier_host::Host for TrayHost {
    fn add_item(&mut self, id: &str, item: notifier_host::Item) {
        let tray_item = TrayItem::new(id.to_string(), item, self.blacklist.clone());
        let id_lower = id.to_lowercase();
        if self.pinned.iter().any(|x| id_lower.contains(x)) {
            self.container
                .pack_start(&tray_item.widget, false, false, 0);
        } else {
            self.container.pack_end(&tray_item.widget, false, false, 0);
        }
        if let Some(old) = self.items.insert(id.to_string(), tray_item) {
            self.container.remove(&old.widget);
        }
    }
    fn remove_item(&mut self, id: &str) {
        if let Some(old) = self.items.remove(id) {
            self.container.remove(&old.widget);
        }
    }
}

struct TrayItem {
    widget: gtk::EventBox,
    task: Option<glib::JoinHandle<()>>,
}
impl Drop for TrayItem {
    fn drop(&mut self) {
        if let Some(task) = &self.task {
            task.abort();
        }
    }
}

impl TrayItem {
    fn new(id: String, item: notifier_host::Item, blacklist: Rc<Vec<String>>) -> Self {
        let widget = gtk::EventBox::new();
        widget.style_context().add_class("tray-item");
        let out = widget.clone();
        let task = glib::MainContext::default().spawn_local(async move {
            if let Err(error) = Self::maintain(&id, widget, item, blacklist).await {
                log::warn!("tray item {id}: {error}");
            }
        });
        Self {
            widget: out,
            task: Some(task),
        }
    }

    async fn maintain(
        id: &str,
        widget: gtk::EventBox,
        mut item: notifier_host::Item,
        blacklist: Rc<Vec<String>>,
    ) -> zbus::Result<()> {
        let title = item.sni.title().await.unwrap_or_default();
        let match_text = format!("{} {}", id, title).to_lowercase();
        if blacklist.iter().any(|entry| match_text.contains(entry)) {
            widget.hide();
            return Ok(());
        }
        let icon = gtk::Image::new();
        widget.add(&icon);
        icon.show();
        if let Err(error) = item.set_menu(&widget).await {
            log::debug!("tray menu unavailable: {error}");
        }
        match item.status().await? {
            notifier_host::Status::Passive => widget.hide(),
            _ => widget.show(),
        }
        widget.set_tooltip_text(Some(&title));
        load_icon(&icon, &item, 18, icon.scale_factor()).await;
        let item = Rc::new(item);
        widget.add_events(gdk::EventMask::BUTTON_PRESS_MASK);
        let clicked = item.clone();
        widget.connect_button_press_event(move |_, event| {
            let (x, y) = (event.root().0 as i32, event.root().1 as i32);
            let primary = event.button() == gdk::BUTTON_PRIMARY;
            let button = event.button();
            let event = event.clone();
            let clicked = clicked.clone();
            glib::MainContext::default().spawn_local(async move {
                let result = match button {
                    gdk::BUTTON_PRIMARY => {
                        let menu = clicked.sni.item_is_menu().await.unwrap_or(false);
                        if menu {
                            clicked.popup_menu(&event, x, y).await
                        } else {
                            clicked.sni.activate(x, y).await
                        }
                    }
                    gdk::BUTTON_MIDDLE => clicked.sni.secondary_activate(x, y).await,
                    gdk::BUTTON_SECONDARY => clicked.popup_menu(&event, x, y).await,
                    _ => Ok(()),
                };
                if let Err(error) = result {
                    log::warn!("tray click failed: {error}");
                    if primary {
                        let _ = clicked.popup_menu(&event, x, y).await;
                    }
                }
            });
            gtk::Inhibit(true)
        });
        let mut statuses = item.sni.receive_new_status().await?;
        let mut titles = item.sni.receive_new_title().await?;
        let mut icons = item.sni.receive_new_icon().await?;
        loop {
            tokio::select! {
                Some(_)=statuses.next()=>match item.status().await? { notifier_host::Status::Passive=>widget.hide(), _=>widget.show() },
                Some(_)=titles.next()=>widget.set_tooltip_text(Some(&item.sni.title().await?)),
                Some(_)=icons.next()=>load_icon(&icon,&item,18,icon.scale_factor()).await,
            }
        }
    }
}

async fn load_icon(icon: &gtk::Image, item: &notifier_host::Item, size: i32, scale: i32) {
    if let Some(pixbuf) = item.icon(size, scale).await {
        let surface = unsafe {
            let ptr = gdk_cairo_surface_create_from_pixbuf(
                pixbuf.as_ptr(),
                scale,
                icon.window().map_or(std::ptr::null_mut(), |v| v.as_ptr()),
            );
            Surface::from_raw_full(ptr)
        };
        icon.set_from_surface(surface.ok().as_ref());
    }
}
