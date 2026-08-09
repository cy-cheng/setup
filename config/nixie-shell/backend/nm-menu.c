#include <NetworkManager.h>
#include <fcntl.h>
#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

static NMClient *client;
static NMDeviceWifi *wifi_device;
static GtkWidget *window;
static GtkWidget *content_box;
static GtkWidget *status_label;
static int lock_fd = -1;

typedef struct {
    NMAccessPoint *ap;
    NMConnection *connection;
} WifiAction;

typedef struct {
    NMConnection *connection;
    NMActiveConnection *active;
} VpnAction;

static void set_status(const char *text) {
    gtk_label_set_text(GTK_LABEL(status_label), text != NULL ? text : "");
}

static gboolean acquire_singleton(void) {
    char path[128];
    snprintf(path, sizeof(path), "/run/user/%u/nixie-nm-menu.lock", getuid());
    lock_fd = open(path, O_RDWR | O_CREAT, 0600);
    if (lock_fd < 0) {
        return TRUE;
    }
    if (flock(lock_fd, LOCK_EX | LOCK_NB) == 0) {
        ftruncate(lock_fd, 0);
        dprintf(lock_fd, "%ld\n", (long)getpid());
        fsync(lock_fd);
        return TRUE;
    }

    lseek(lock_fd, 0, SEEK_SET);
    char buffer[32] = {0};
    if (read(lock_fd, buffer, sizeof(buffer) - 1) > 0) {
        long pid = strtol(buffer, NULL, 10);
        if (pid > 1) {
            kill((pid_t)pid, SIGTERM);
        }
    }
    close(lock_fd);
    lock_fd = -1;
    return FALSE;
}

static const char *signal_icon(guint strength) {
    if (strength >= 75) return "󰤨";
    if (strength >= 50) return "󰤥";
    if (strength >= 25) return "󰤢";
    return "󰤟";
}

static char *ssid_text(NMAccessPoint *ap) {
    GBytes *ssid = nm_access_point_get_ssid(ap);
    if (ssid == NULL) return g_strdup("Hidden network");
    gsize length = 0;
    const guint8 *bytes = g_bytes_get_data(ssid, &length);
    char *text = nm_utils_ssid_to_utf8(bytes, length);
    return text != NULL && text[0] != '\0' ? text : g_strdup("Hidden network");
}

static gboolean ap_secured(NMAccessPoint *ap) {
    return nm_access_point_get_flags(ap) != NM_802_11_AP_FLAGS_NONE ||
           nm_access_point_get_wpa_flags(ap) != NM_802_11_AP_SEC_NONE ||
           nm_access_point_get_rsn_flags(ap) != NM_802_11_AP_SEC_NONE;
}

static NMActiveConnection *active_for_uuid(const char *uuid) {
    const GPtrArray *active = nm_client_get_active_connections(client);
    for (guint i = 0; active != NULL && i < active->len; i++) {
        NMActiveConnection *candidate = g_ptr_array_index((GPtrArray *)active, i);
        if (g_strcmp0(nm_active_connection_get_uuid(candidate), uuid) == 0) {
            return candidate;
        }
    }
    return NULL;
}

static void activate_done(GObject *source, GAsyncResult *result, gpointer data) {
    (void)data;
    GError *error = NULL;
    NMActiveConnection *active =
        nm_client_activate_connection_finish(NM_CLIENT(source), result, &error);
    if (active == NULL) {
        set_status(error != NULL ? error->message : "Connection failed");
        g_clear_error(&error);
        return;
    }
    gtk_main_quit();
}

static void add_activate_done(GObject *source, GAsyncResult *result, gpointer data) {
    (void)data;
    GError *error = NULL;
    NMActiveConnection *active =
        nm_client_add_and_activate_connection_finish(NM_CLIENT(source), result,
                                                     &error);
    if (active == NULL) {
        set_status(error != NULL ? error->message : "Connection failed");
        g_clear_error(&error);
        return;
    }
    gtk_main_quit();
}

static void wifi_action_free(gpointer data, GClosure *closure) {
    (void)closure;
    WifiAction *action = data;
    g_clear_object(&action->ap);
    if (action->connection != NULL) g_object_unref(action->connection);
    g_free(action);
}

static void wifi_clicked(GtkButton *button, gpointer data) {
    (void)button;
    WifiAction *action = data;
    set_status("Connecting…");
    if (action->connection != NULL) {
        nm_client_activate_connection_async(
            client, action->connection, NM_DEVICE(wifi_device),
            nm_object_get_path(NM_OBJECT(action->ap)), NULL, activate_done, NULL);
    } else {
        nm_client_add_and_activate_connection_async(
            client, NULL, NM_DEVICE(wifi_device),
            nm_object_get_path(NM_OBJECT(action->ap)), NULL, add_activate_done, NULL);
    }
}

static gint compare_ap(gconstpointer left, gconstpointer right) {
    NMAccessPoint *a = *(NMAccessPoint *const *)left;
    NMAccessPoint *b = *(NMAccessPoint *const *)right;
    return (gint)nm_access_point_get_strength(b) -
           (gint)nm_access_point_get_strength(a);
}

static GtkWidget *section_title(const char *text) {
    GtkWidget *label = gtk_label_new(text);
    gtk_widget_set_halign(label, GTK_ALIGN_START);
    gtk_style_context_add_class(gtk_widget_get_style_context(label), "section-title");
    return label;
}

static void add_wifi_rows(GtkWidget *box) {
    if (wifi_device == NULL) {
        GtkWidget *label = gtk_label_new("No Wi‑Fi device detected");
        gtk_widget_set_halign(label, GTK_ALIGN_START);
        gtk_box_pack_start(GTK_BOX(box), label, FALSE, FALSE, 4);
        return;
    }

    NMAccessPoint *active_ap = nm_device_wifi_get_active_access_point(wifi_device);
    const GPtrArray *all = nm_device_wifi_get_access_points(wifi_device);
    GHashTable *seen = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    GPtrArray *aps = g_ptr_array_new_with_free_func(g_object_unref);

    for (guint i = 0; all != NULL && i < all->len; i++) {
        NMAccessPoint *ap = g_ptr_array_index((GPtrArray *)all, i);
        char *ssid = ssid_text(ap);
        if (g_hash_table_contains(seen, ssid)) {
            g_free(ssid);
            continue;
        }
        g_hash_table_add(seen, ssid);
        g_ptr_array_add(aps, g_object_ref(ap));
    }
    g_ptr_array_sort(aps, compare_ap);

    for (guint i = 0; i < aps->len; i++) {
        NMAccessPoint *ap = g_ptr_array_index(aps, i);
        char *ssid = ssid_text(ap);
        gboolean is_active = ap == active_ap;
        gboolean secured = ap_secured(ap);
        guint strength = nm_access_point_get_strength(ap);

        GtkWidget *button = gtk_button_new();
        GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 9);
        GtkWidget *icon = gtk_label_new(signal_icon(strength));
        GtkWidget *name = gtk_label_new(ssid);
        GtkWidget *lock = gtk_label_new(secured ? "󰌾" : "");
        GtkWidget *state = gtk_label_new(is_active ? "Connected" : "");
        gtk_widget_set_halign(name, GTK_ALIGN_START);
        gtk_widget_set_hexpand(name, TRUE);
        gtk_style_context_add_class(gtk_widget_get_style_context(icon), "wifi-icon");
        gtk_style_context_add_class(gtk_widget_get_style_context(state), "connected");
        gtk_box_pack_start(GTK_BOX(row), icon, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(row), name, TRUE, TRUE, 0);
        gtk_box_pack_start(GTK_BOX(row), state, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(row), lock, FALSE, FALSE, 0);
        gtk_container_add(GTK_CONTAINER(button), row);
        gtk_style_context_add_class(gtk_widget_get_style_context(button), "network-row");
        gtk_widget_set_sensitive(button, !is_active);

        WifiAction *action = g_new0(WifiAction, 1);
        action->ap = g_object_ref(ap);
        GPtrArray *compatible =
            nm_access_point_filter_connections(ap, nm_client_get_connections(client));
        if (compatible != NULL && compatible->len > 0) {
            action->connection = g_object_ref(g_ptr_array_index(compatible, 0));
        }
        if (compatible != NULL) g_ptr_array_unref(compatible);
        g_signal_connect_data(button, "clicked", G_CALLBACK(wifi_clicked), action,
                              wifi_action_free, 0);
        gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
        g_free(ssid);
    }

    g_ptr_array_unref(aps);
    g_hash_table_unref(seen);
}

static void vpn_action_free(gpointer data, GClosure *closure) {
    (void)closure;
    VpnAction *action = data;
    g_clear_object(&action->connection);
    g_clear_object(&action->active);
    g_free(action);
}

static void deactivate_done(GObject *source, GAsyncResult *result, gpointer data) {
    (void)data;
    GError *error = NULL;
    if (!nm_client_deactivate_connection_finish(NM_CLIENT(source), result, &error)) {
        set_status(error != NULL ? error->message : "Could not disconnect VPN");
        g_clear_error(&error);
        return;
    }
    gtk_main_quit();
}

static void vpn_clicked(GtkButton *button, gpointer data) {
    (void)button;
    VpnAction *action = data;
    if (action->active != NULL) {
        set_status("Disconnecting VPN…");
        nm_client_deactivate_connection_async(client, action->active, NULL,
                                              deactivate_done, NULL);
    } else {
        set_status("Connecting VPN…");
        nm_client_activate_connection_async(client, action->connection, NULL, NULL,
                                            NULL, activate_done, NULL);
    }
}

static void add_vpn_rows(GtkWidget *box) {
    const GPtrArray *connections = nm_client_get_connections(client);
    gboolean added_title = FALSE;
    for (guint i = 0; connections != NULL && i < connections->len; i++) {
        NMConnection *connection = g_ptr_array_index((GPtrArray *)connections, i);
        const char *type = nm_connection_get_connection_type(connection);
        if (g_strcmp0(type, NM_SETTING_VPN_SETTING_NAME) != 0 &&
            g_strcmp0(type, NM_SETTING_WIREGUARD_SETTING_NAME) != 0) {
            continue;
        }
        if (!added_title) {
            gtk_box_pack_start(GTK_BOX(box), section_title("VPN"), FALSE, FALSE, 5);
            added_title = TRUE;
        }
        NMActiveConnection *active = active_for_uuid(nm_connection_get_uuid(connection));
        char *label = g_strdup_printf("󰌾  %s%s", nm_connection_get_id(connection),
                                      active != NULL ? "    Connected" : "");
        GtkWidget *button = gtk_button_new_with_label(label);
        gtk_style_context_add_class(gtk_widget_get_style_context(button), "network-row");
        gtk_widget_set_halign(gtk_bin_get_child(GTK_BIN(button)), GTK_ALIGN_START);
        VpnAction *action = g_new0(VpnAction, 1);
        action->connection = g_object_ref(connection);
        if (active != NULL) action->active = g_object_ref(active);
        g_signal_connect_data(button, "clicked", G_CALLBACK(vpn_clicked), action,
                              vpn_action_free, 0);
        gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
        g_free(label);
    }
}

static void scan_done(GObject *source, GAsyncResult *result, gpointer data) {
    (void)data;
    GError *error = NULL;
    if (!nm_device_wifi_request_scan_finish(NM_DEVICE_WIFI(source), result, &error)) {
        set_status(error != NULL ? error->message : "Scan failed");
        g_clear_error(&error);
    } else {
        set_status("Scan requested — reopen shortly for fresh results");
    }
}

static void scan_clicked(GtkButton *button, gpointer data) {
    (void)button;
    (void)data;
    if (wifi_device != NULL) {
        set_status("Scanning…");
        nm_device_wifi_request_scan_async(wifi_device, NULL, scan_done, NULL);
    }
}

static gboolean wifi_switched(GtkSwitch *widget, gboolean state, gpointer data) {
    (void)widget;
    (void)data;
    nm_client_wireless_set_enabled(client, state);
    set_status(state ? "Wi‑Fi enabled" : "Wi‑Fi disabled");
    return FALSE;
}

static gboolean key_pressed(GtkWidget *widget, GdkEventKey *event, gpointer data) {
    (void)widget;
    (void)data;
    if (event->keyval == GDK_KEY_Escape) {
        gtk_main_quit();
        return TRUE;
    }
    return FALSE;
}

static void manage_clicked(GtkButton *button, gpointer data) {
    (void)button;
    (void)data;
    GError *error = NULL;
    if (!g_spawn_command_line_async("nm-connection-editor", &error)) {
        set_status(error != NULL ? error->message : "Could not open network settings");
        g_clear_error(&error);
        return;
    }
    gtk_main_quit();
}

static void load_css(void) {
    const char *css =
        "window { background: rgba(16, 11, 8, 0.58); border: 1px solid #d78924; border-radius: 10px; color: #f2e7d5; }"
        ".menu-content { padding: 12px; }"
        ".title { font-weight: 700; font-size: 15px; color: #f4a62a; }"
        ".section-title { margin-top: 7px; color: #9d8b78; font-weight: 700; }"
        ".network-row { min-height: 35px; padding: 2px 8px; border: 0; border-radius: 6px; background: transparent; color: #f2e7d5; }"
        ".network-row:hover { background: rgba(42, 27, 18, 0.82); }"
        ".network-row:disabled { color: #f4a62a; opacity: 1; }"
        ".wifi-icon { color: #f4a62a; font-family: 'Symbols Nerd Font Mono'; }"
        ".connected { color: #87c66b; font-size: 11px; }"
        ".status { color: #9d8b78; font-size: 11px; margin-top: 5px; }"
        "button.flat { min-height: 28px; padding: 0 8px; background: transparent; color: #d7c7b5; border: 1px solid #4a3323; border-radius: 6px; }";
    GtkCssProvider *provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(provider, css, -1, NULL);
    gtk_style_context_add_provider_for_screen(
        gdk_screen_get_default(), GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
}

int main(int argc, char **argv) {
    if (!acquire_singleton()) return 0;
    gtk_init(&argc, &argv);
    load_css();

    GError *error = NULL;
    client = nm_client_new(NULL, &error);
    if (client == NULL) {
        g_printerr("nm-menu: %s\n", error->message);
        g_error_free(error);
        return 1;
    }
    const GPtrArray *devices = nm_client_get_devices(client);
    for (guint i = 0; devices != NULL && i < devices->len; i++) {
        NMDevice *device = g_ptr_array_index((GPtrArray *)devices, i);
        if (NM_IS_DEVICE_WIFI(device)) {
            wifi_device = NM_DEVICE_WIFI(device);
            break;
        }
    }

    window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GdkVisual *visual = gdk_screen_get_rgba_visual(gtk_widget_get_screen(window));
    if (visual != NULL) gtk_widget_set_visual(window, visual);
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_resizable(GTK_WINDOW(window), FALSE);
    gtk_widget_set_size_request(window, 360, -1);
    gtk_layer_init_for_window(GTK_WINDOW(window));
    gtk_layer_set_namespace(GTK_WINDOW(window), "nixie-network-menu");
    gtk_layer_set_layer(GTK_WINDOW(window), GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_anchor(GTK_WINDOW(window), GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(window), GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_margin(GTK_WINDOW(window), GTK_LAYER_SHELL_EDGE_TOP, 4);
    const char *left_value = getenv("NIXIE_POPUP_LEFT");
    int left_margin = left_value != NULL ? atoi(left_value) : 12;
    gtk_layer_set_margin(GTK_WINDOW(window), GTK_LAYER_SHELL_EDGE_LEFT,
                         left_margin > 0 ? left_margin : 12);
    gtk_layer_set_keyboard_mode(GTK_WINDOW(window),
                                GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
    g_signal_connect(window, "key-press-event", G_CALLBACK(key_pressed), NULL);

    content_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    gtk_style_context_add_class(gtk_widget_get_style_context(content_box), "menu-content");
    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *title = gtk_label_new("Network");
    gtk_style_context_add_class(gtk_widget_get_style_context(title), "title");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_widget_set_hexpand(title, TRUE);
    GtkWidget *scan = gtk_button_new_with_label("󰑐  Scan");
    gtk_style_context_add_class(gtk_widget_get_style_context(scan), "flat");
    g_signal_connect(scan, "clicked", G_CALLBACK(scan_clicked), NULL);
    GtkWidget *toggle = gtk_switch_new();
    gtk_switch_set_active(GTK_SWITCH(toggle), nm_client_wireless_get_enabled(client));
    g_signal_connect(toggle, "state-set", G_CALLBACK(wifi_switched), NULL);
    gtk_box_pack_start(GTK_BOX(header), title, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(header), scan, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(header), toggle, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(content_box), header, FALSE, FALSE, 2);
    gtk_box_pack_start(GTK_BOX(content_box), section_title("Wi‑Fi"), FALSE, FALSE, 3);

    GtkWidget *list_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    add_wifi_rows(list_box);
    add_vpn_rows(list_box);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_widget_set_size_request(scroll, -1, 390);
    gtk_container_add(GTK_CONTAINER(scroll), list_box);
    gtk_box_pack_start(GTK_BOX(content_box), scroll, TRUE, TRUE, 2);

    status_label = gtk_label_new("");
    gtk_label_set_line_wrap(GTK_LABEL(status_label), TRUE);
    gtk_widget_set_halign(status_label, GTK_ALIGN_START);
    gtk_style_context_add_class(gtk_widget_get_style_context(status_label), "status");
    gtk_box_pack_start(GTK_BOX(content_box), status_label, FALSE, FALSE, 0);
    GtkWidget *manage = gtk_button_new_with_label("Advanced network settings");
    gtk_style_context_add_class(gtk_widget_get_style_context(manage), "flat");
    g_signal_connect(manage, "clicked", G_CALLBACK(manage_clicked), NULL);
    gtk_box_pack_start(GTK_BOX(content_box), manage, FALSE, FALSE, 2);
    gtk_container_add(GTK_CONTAINER(window), content_box);

    gtk_widget_show_all(window);
    gtk_main();

    gtk_widget_destroy(window);
    g_clear_object(&client);
    if (lock_fd >= 0) close(lock_fd);
    return 0;
}
