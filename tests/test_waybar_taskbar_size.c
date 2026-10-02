/* Loaded only into an isolated test Waybar. Exercise a real GTK allocation
 * increase, then remove the sibling that caused it. No desktop input events. */
#include <gtk/gtk.h>
#include <stdlib.h>

static GtkWidget *window, *pulse, *fixture;
static int baseline, enlarged;
static int image_count, largest_image, original_count;
static gboolean fixture_focused;

static void inspect_images(GtkWidget *widget, gpointer unused) {
    (void)unused;
    if (GTK_IS_IMAGE(widget)) {
        int minimum, natural;
        gtk_widget_get_preferred_height(widget, &minimum, &natural);
        image_count++;
        largest_image = MAX(largest_image, natural);
    }
    if (GTK_IS_BUTTON(widget)) {
        gchar *title = gtk_widget_get_tooltip_text(widget);
        if (g_strcmp0(title, "Taskbar regression fixture") == 0)
            fixture_focused = gtk_style_context_has_class(
                gtk_widget_get_style_context(widget), "focused");
        g_free(title);
    }
    if (GTK_IS_CONTAINER(widget))
        gtk_container_foreach(GTK_CONTAINER(widget), inspect_images, NULL);
}

static int record(const char *phase) {
    image_count = largest_image = 0;
    fixture_focused = FALSE;
    inspect_images(window, NULL);
    int height = gtk_widget_get_allocated_height(window);
    g_print("TASKBAR_SIZE %s height=%d images=%d largest_image=%d\n",
            phase, height, image_count, largest_image);
    return height;
}

static gboolean start(gpointer unused) {
    (void)unused;
    GList *windows = gtk_window_list_toplevels();
    for (GList *entry = windows; entry; entry = entry->next) {
        if (gtk_widget_get_visible(entry->data)) {
            window = entry->data;
            break;
        }
    }
    g_list_free(windows);
    if (!window) {
        g_printerr("FAIL: no test bar; a live Wayland output is required\n");
        exit(1);
    }
    baseline = record("baseline");
    original_count = image_count;
    if (!image_count) {
        g_printerr("FAIL: open at least one application for the taskbar test\n");
        exit(1);
    }
    return G_SOURCE_REMOVE;
}

static gboolean open_fixture(gpointer unused) {
    (void)unused;
    fixture = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(fixture), "Taskbar regression fixture");
    gtk_window_set_default_size(GTK_WINDOW(fixture), 320, 80);
    gtk_container_add(GTK_CONTAINER(fixture), gtk_label_new("Checking taskbar updates"));
    gtk_widget_show_all(fixture);
    gtk_window_present(GTK_WINDOW(fixture));
    return G_SOURCE_REMOVE;
}

static gboolean close_fixture(gpointer unused) {
    (void)unused;
    record("window-opened");
    if (image_count != original_count + 1 || !fixture_focused) {
        g_printerr("FAIL: taskbar did not follow the new window and focus event\n");
        exit(1);
    }
    gtk_widget_destroy(fixture);
    return G_SOURCE_REMOVE;
}

static gboolean grow(gpointer unused) {
    (void)unused;
    record("window-closed");
    if (image_count != original_count) {
        g_printerr("FAIL: taskbar did not remove the closed window\n");
        exit(1);
    }
    pulse = gtk_label_new("Taskbar size regression test");
    gtk_widget_set_size_request(pulse, 1, baseline + 25);
    gtk_container_add(GTK_CONTAINER(gtk_bin_get_child(GTK_BIN(window))), pulse);
    gtk_widget_show(pulse);
    return G_SOURCE_REMOVE;
}

static gboolean shrink(gpointer unused) {
    (void)unused;
    enlarged = record("enlarged");
    gtk_widget_destroy(pulse);
    return G_SOURCE_REMOVE;
}

static gboolean finish(gpointer unused) {
    (void)unused;
    int recovered = record("recovered");
    if (enlarged != baseline + 25 || recovered != baseline || largest_image != 18) {
        g_printerr("FAIL: expected %d -> %d -> %d and 18px icons\n",
                   baseline, baseline + 25, baseline);
        exit(1);
    }
    g_print("PASS: window/focus updates and height recovery with fixed icons\n");
    exit(0);
}

__attribute__((constructor)) static void init(void) {
    g_timeout_add(700, start, NULL);
    g_timeout_add(1000, open_fixture, NULL);
    g_timeout_add(1800, close_fixture, NULL);
    g_timeout_add(2600, grow, NULL);
    g_timeout_add(3400, shrink, NULL);
    g_timeout_add(4400, finish, NULL);
}
