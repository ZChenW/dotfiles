/* Live GTK/Wayland harness; fake helper, real per-window output selection. */
#include "../configs/config/waybar/cffi/brightness.c"

static GtkWidget *windows[2], *containers[2];
static Brightness *controls[2];
static int phase = 0, ticks = 0;
static GtkContainer *root_widget(wbcffi_module *obj) { return GTK_CONTAINER(obj); }
static void update(wbcffi_module *obj) { (void)obj; }
static void check(gboolean ok, const char *message) {
    if (!ok) { g_printerr("FAIL: %s\n", message); exit(1); }
}
static gboolean step(gpointer data) {
    (void)data;
    if (++ticks > 160) { g_printerr("FAIL: timeout phase %d\n", phase); exit(1); }
    if (phase == 0) {
        if (!controls[0]->ready || !controls[1]->ready) return G_SOURCE_CONTINUE;
        check(strcmp(controls[0]->output, controls[1]->output), "monitors must differ");
        g_print("Mapped %s and %s from their GTK windows\n", controls[0]->output, controls[1]->output);
        gtk_range_set_value(GTK_RANGE(controls[0]->scale), 41);
        gtk_range_set_value(GTK_RANGE(controls[0]->scale), 42);
        gtk_range_set_value(GTK_RANGE(controls[0]->scale), 43);
        gtk_range_set_value(GTK_RANGE(controls[1]->scale), 61);
        phase++;
    } else if (phase == 1) {
        if (controls[0]->pending || controls[1]->pending || controls[0]->process || controls[1]->process) return G_SOURCE_CONTINUE;
        check(controls[0]->value == 43 && controls[1]->value == 61, "latest drag targets read back separately");
        GdkEventScroll event = {0}; event.direction = GDK_SCROLL_UP;
        scroll(controls[0]->level, &event, controls[0]);
        event.direction = GDK_SCROLL_DOWN;
        scroll(controls[1]->level, &event, controls[1]);
        phase++;
    } else if (phase == 2) {
        if (controls[0]->pending || controls[1]->pending || controls[0]->process || controls[1]->process) return G_SOURCE_CONTINUE;
        check(controls[0]->value == 48 && controls[1]->value == 56, "wheel targets remain per window");
        for (int i = 0; i < 2; i++) {
            request(controls[i], FALSE);
            wbcffi_deinit(controls[i]);
            gtk_widget_destroy(windows[i]);
        }
        phase++;
        ticks = 0;
    } else if (ticks > 12) {
        g_print("PASS: per-window drag, coalescing, wheel, readback, async teardown\n");
        gtk_main_quit();
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}
int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    GdkDisplay *display = gdk_display_get_default();
    check(gdk_display_get_n_monitors(display) >= 2, "two real monitors required");
    for (int i = 0; i < 2; i++) {
        windows[i] = gtk_window_new(GTK_WINDOW_TOPLEVEL);
        gtk_layer_init_for_window(GTK_WINDOW(windows[i]));
        gtk_layer_set_namespace(GTK_WINDOW(windows[i]), "brightness-test");
        gtk_layer_set_monitor(GTK_WINDOW(windows[i]), gdk_display_get_monitor(display, i));
        gtk_layer_set_anchor(GTK_WINDOW(windows[i]), GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
        containers[i] = gtk_event_box_new();
        gtk_container_add(GTK_CONTAINER(windows[i]), containers[i]);
        InitInfo info = {(wbcffi_module *)containers[i], "test", root_widget, update};
        controls[i] = wbcffi_init(&info, NULL, 0);
        gtk_widget_show_all(windows[i]);
    }
    g_timeout_add(100, step, NULL);
    gtk_main();
    return 0;
}
