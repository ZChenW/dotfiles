/* Continuous dragging must reach hardware before the gesture ends. */
#include "../configs/config/waybar/cffi/brightness.c"

static Brightness *control;
static GtkWidget *window;
static guint ticks;
static GtkContainer *root_widget(wbcffi_module *obj) { return GTK_CONTAINER(obj); }
static void update(wbcffi_module *obj) { (void)obj; }
static gboolean drag(gpointer unused) {
    (void)unused;
    if (!control->ready) return G_SOURCE_CONTINUE;
    ticks++;
    if (ticks <= 24) {
        gtk_range_set_value(GTK_RANGE(control->scale), 50 + ticks);
        if (ticks == 20 && !g_file_test(g_getenv("TEST_WRITES"), G_FILE_TEST_EXISTS)) {
            g_printerr("FAIL: continuous drag has sent no hardware update after 1 second\n");
            exit(1);
        }
    } else if (!control->pending && !control->process && !control->debounce) {
        if (control->value != 74) { g_printerr("FAIL: final target lost\n"); exit(1); }
        wbcffi_deinit(control);
        gtk_widget_destroy(window);
        g_print("PASS: continuous drag updates hardware within 1 second; final target retained\n");
        gtk_main_quit();
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}
int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_layer_init_for_window(GTK_WINDOW(window));
    gtk_layer_set_namespace(GTK_WINDOW(window), "brightness-latency-test");
    gtk_layer_set_anchor(GTK_WINDOW(window), GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    GtkWidget *container = gtk_event_box_new();
    gtk_container_add(GTK_CONTAINER(window), container);
    InitInfo info = {(wbcffi_module *)container, "test", root_widget, update};
    control = wbcffi_init(&info, NULL, 0);
    gtk_widget_show_all(window);
    g_timeout_add(50, drag, NULL);
    gtk_main();
    return 0;
}
