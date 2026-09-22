/* Waybar CFFI ABI 1 — per-output slider + level icon only.
 * Placed inside native group/ddcutil so the bar keeps its drawer, dividers,
 * and module chrome. Day / sleep / night stay native custom modules.
 * ABI: https://github.com/Alexays/Waybar/blob/master/include/modules/cffi.hpp
 */
#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef struct wbcffi_module wbcffi_module;
typedef struct {
    wbcffi_module *obj;
    const char *waybar_version;
    GtkContainer *(*get_root_widget)(wbcffi_module *);
    void (*queue_update)(wbcffi_module *);
} InitInfo;
typedef struct { const char *key; const char *value; } ConfigEntry;
const size_t wbcffi_version = 1;

static const char *level_icons[] = {
    "", "", "", "", "", "", "", "", ""
};

typedef struct {
    GtkWidget *root, *scale, *level, *level_label;
    gchar *output, *helper;
    GSubprocess *process;
    guint debounce, poll;
    int refs, value, desired;
    gboolean closed, ready, updating, pending, writing;
} Brightness;

static void request(Brightness *b, gboolean write);
static void update_level_icon(Brightness *b);
static void tooltip(Brightness *b, const char *error);

static void unref(Brightness *b) {
    if (--b->refs) return;
    g_free(b->output);
    g_free(b->helper);
    g_free(b);
}

static gchar *window_output(GtkWidget *widget) {
    GtkWidget *top = gtk_widget_get_toplevel(widget);
    if (!GTK_IS_WINDOW(top) || !gtk_widget_get_realized(top)) return NULL;
    GdkDisplay *display = gtk_widget_get_display(top);
    GdkMonitor *monitor = gtk_layer_is_layer_window(GTK_WINDOW(top))
        ? gtk_layer_get_monitor(GTK_WINDOW(top)) : NULL;
    if (!monitor)
        monitor = gdk_display_get_monitor_at_window(display, gtk_widget_get_window(top));
    for (int i = 0; i < gdk_display_get_n_monitors(display); i++) {
        if (gdk_display_get_monitor(display, i) == monitor) {
            G_GNUC_BEGIN_IGNORE_DEPRECATIONS
            gchar *name = gdk_screen_get_monitor_plug_name(gdk_display_get_default_screen(display), i);
            G_GNUC_END_IGNORE_DEPRECATIONS
            return name;
        }
    }
    return NULL;
}

static void update_level_icon(Brightness *b) {
    if (!b->level_label) return;
    int last = (int)G_N_ELEMENTS(level_icons) - 1;
    int idx = last <= 0 ? 0 : CLAMP((b->value * last + 50) / 100, 0, last);
    gtk_label_set_text(GTK_LABEL(b->level_label), level_icons[idx]);
}

static void tooltip(Brightness *b, const char *error) {
    gchar *text = error
        ? g_strdup_printf("%s：%s\n移入重试", b->output ? b->output : "此屏幕", error)
        : g_strdup_printf("此屏幕亮度：%d%%\n拖动滑块或滚轮调节", b->value);
    gtk_widget_set_tooltip_text(b->scale, text);
    if (b->level) gtk_widget_set_tooltip_text(b->level, text);
    g_free(text);
}

static gboolean flush(gpointer data) {
    Brightness *b = data;
    b->debounce = 0;
    if (!b->process && b->pending) request(b, TRUE);
    return G_SOURCE_REMOVE;
}

static void done(GObject *source, GAsyncResult *result, gpointer data) {
    Brightness *b = data;
    gchar *out = NULL, *err = NULL;
    GError *error = NULL;
    gboolean ok = g_subprocess_communicate_utf8_finish(G_SUBPROCESS(source), result, &out, &err, &error);
    if (ok) ok = g_subprocess_get_successful(G_SUBPROCESS(source));
    g_clear_object(&b->process);
    if (!b->closed) {
        if (!ok) {
            b->ready = FALSE;
            gtk_widget_set_sensitive(b->scale, FALSE);
            tooltip(b, "亮度读取或设置失败");
            g_warning("Waybar brightness %s: %s", b->output, error ? error->message : (err ? err : "command failed"));
        } else if (!b->writing && !b->pending) {
            int percent;
            if (out && sscanf(out, "%*[^,],%*d,%*d,%d", &percent) == 1 && percent >= 0 && percent <= 100) {
                b->value = percent;
                b->ready = TRUE;
                b->updating = TRUE;
                gtk_range_set_value(GTK_RANGE(b->scale), percent);
                b->updating = FALSE;
                gtk_widget_set_sensitive(b->scale, TRUE);
                update_level_icon(b);
                tooltip(b, NULL);
            } else {
                b->ready = FALSE;
                gtk_widget_set_sensitive(b->scale, FALSE);
                tooltip(b, "亮度数据无效");
            }
        }
        if (b->pending) {
            if (!b->debounce) b->debounce = g_timeout_add(150, flush, b);
        } else if (b->writing) {
            /* Keep the optimistic UI value; a later poll can reconcile.
             * Skipping immediate readback avoids a second DDC round-trip per drag. */
            b->writing = FALSE;
            b->ready = TRUE;
            gtk_widget_set_sensitive(b->scale, TRUE);
            tooltip(b, NULL);
        }
    }
    g_clear_error(&error);
    g_free(out);
    g_free(err);
    unref(b);
}

static void request(Brightness *b, gboolean write) {
    if (b->closed || b->process) return;
    gchar *output = window_output(b->root);
    if (!output || !*output || (b->output && strcmp(output, b->output))) {
        g_free(output);
        b->pending = FALSE;
        b->ready = FALSE;
        gtk_widget_set_sensitive(b->scale, FALSE);
        tooltip(b, "无法确定所在屏幕");
        return;
    }
    if (!b->output) b->output = output; else g_free(output);
    gchar value[16];
    g_snprintf(value, sizeof(value), "%d", b->desired);
    const gchar *argv[] = {"timeout", "10s", b->helper, "--output", b->output,
                           write ? "--set-percent" : "--get", write ? value : NULL, NULL};
    GError *error = NULL;
    b->writing = write;
    if (write) b->pending = FALSE;
    b->process = g_subprocess_newv(argv, G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE, &error);
    if (!b->process) {
        tooltip(b, "无法启动亮度控制");
        g_warning("Waybar brightness: %s", error->message);
        g_clear_error(&error);
        return;
    }
    b->refs++;
    g_subprocess_communicate_utf8_async(b->process, NULL, NULL, done, b);
}

static void set_value(Brightness *b, int value) {
    b->desired = CLAMP(value, 5, 100);
    b->value = b->desired;
    b->pending = TRUE;
    b->updating = TRUE;
    gtk_range_set_value(GTK_RANGE(b->scale), b->desired);
    b->updating = FALSE;
    update_level_icon(b);
    tooltip(b, NULL);
    if (b->debounce) g_source_remove(b->debounce);
    b->debounce = g_timeout_add(150, flush, b);
}

static void changed(GtkRange *range, gpointer data) {
    Brightness *b = data;
    if (!b->updating && b->ready) set_value(b, (int)lround(gtk_range_get_value(range)));
}

static gboolean scroll(GtkWidget *widget, GdkEventScroll *event, gpointer data) {
    (void)widget;
    Brightness *b = data;
    if (!b->ready) { request(b, FALSE); return TRUE; }
    int step = event->direction == GDK_SCROLL_UP ? 5 : event->direction == GDK_SCROLL_DOWN ? -5 : 0;
    if (event->direction == GDK_SCROLL_SMOOTH)
        step = event->delta_y < 0 ? 5 : event->delta_y > 0 ? -5 : 0;
    if (step) set_value(b, b->value + step);
    return TRUE;
}

static gboolean poll(gpointer data) {
    Brightness *b = data;
    if (!b->pending) request(b, FALSE);
    return G_SOURCE_CONTINUE;
}

static void mapped(GtkWidget *widget, gpointer data) {
    (void)widget;
    request(data, FALSE);
}

void *wbcffi_init(const InitInfo *info, const ConfigEntry *entries, size_t count) {
    (void)entries; (void)count;
    Brightness *b = g_new0(Brightness, 1);
    b->refs = 1;
    b->root = GTK_WIDGET(info->get_root_widget(info->obj));
    b->helper = g_build_filename(g_get_user_config_dir(), "niri/scripts/brightness.sh", NULL);

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    b->scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 5, 100, 1);
    gtk_widget_set_name(b->scale, "backlight-slider");
    gtk_style_context_add_class(gtk_widget_get_style_context(b->scale), "per-output-brightness");
    gtk_scale_set_draw_value(GTK_SCALE(b->scale), FALSE);
    gtk_widget_set_sensitive(b->scale, FALSE);
    atk_object_set_name(gtk_widget_get_accessible(b->scale), "此屏幕亮度");
    g_signal_connect(b->scale, "value-changed", G_CALLBACK(changed), b);
    g_signal_connect(b->scale, "scroll-event", G_CALLBACK(scroll), b);

    b->level = gtk_event_box_new();
    gtk_widget_set_name(b->level, "backlight");
    b->level_label = gtk_label_new(level_icons[0]);
    gtk_container_add(GTK_CONTAINER(b->level), b->level_label);
    g_signal_connect(b->level, "scroll-event", G_CALLBACK(scroll), b);
    gtk_widget_add_events(b->level, GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK);
    atk_object_set_name(gtk_widget_get_accessible(b->level), "此屏幕亮度图标");

    gtk_box_pack_start(GTK_BOX(box), b->scale, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), b->level, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(b->root), box);

    g_signal_connect(b->root, "map", G_CALLBACK(mapped), b);
    b->poll = g_timeout_add_seconds(30, poll, b);
    update_level_icon(b);
    tooltip(b, "正在读取亮度");
    gtk_widget_show_all(box);
    return b;
}

void wbcffi_deinit(void *instance) {
    Brightness *b = instance;
    b->closed = TRUE;
    if (b->debounce) g_source_remove(b->debounce);
    if (b->poll) g_source_remove(b->poll);
    g_signal_handlers_disconnect_by_data(b->root, b);
    unref(b);
}
