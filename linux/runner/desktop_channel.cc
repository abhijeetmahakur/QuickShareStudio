#include "desktop_channel.h"

#include <cstring>

struct _DesktopChannel {
  FlMethodChannel* channel;
  GtkWindow* window;
  gulong delete_handler;
  // When true, closing the window hides it (the tray icon brings it back).
  gboolean close_to_tray;
};

static void respond(FlMethodCall* call, FlValue* result) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_success(call, result, &error)) {
    g_warning("quickshare/desktop: could not respond: %s", error->message);
  }
}

static void respond_error(FlMethodCall* call, const gchar* code,
                          const gchar* message) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_error(call, code, message, nullptr, &error)) {
    g_warning("quickshare/desktop: could not respond: %s", error->message);
  }
}

// GTK converts whatever image format the owner offers (PNG, JPEG, BMP, ...) into
// a pixbuf; Dart always receives PNG bytes, or null when there is no image.
static void clipboard_image_received(GtkClipboard* clipboard, GdkPixbuf* pixbuf,
                                     gpointer user_data) {
  FlMethodCall* call = FL_METHOD_CALL(user_data);
  if (pixbuf == nullptr) {
    g_autoptr(FlValue) none = fl_value_new_null();
    respond(call, none);
    g_object_unref(call);
    return;
  }
  gchar* buffer = nullptr;
  gsize size = 0;
  g_autoptr(GError) error = nullptr;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &size, "png", &error,
                                 nullptr)) {
    respond_error(call, "encode_failed", error->message);
    g_object_unref(call);
    return;
  }
  g_autoptr(FlValue) result = fl_value_new_uint8_list(
      reinterpret_cast<const uint8_t*>(buffer), size);
  g_free(buffer);
  respond(call, result);
  g_object_unref(call);
}

static void read_clipboard_image(FlMethodCall* call) {
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_request_image(clipboard, clipboard_image_received,
                              g_object_ref(call));
}

static void write_clipboard_image(FlMethodCall* call, FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
    respond_error(call, "bad_args", "Expected the image bytes.");
    return;
  }
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  g_autoptr(GError) write_error = nullptr;
  g_autoptr(GError) close_error = nullptr;
  const gboolean written =
      gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(args),
                              fl_value_get_length(args), &write_error);
  // Always close: a loader finalized while open logs a warning.
  const gboolean closed = gdk_pixbuf_loader_close(loader, &close_error);
  if (!written || !closed) {
    const GError* error = write_error != nullptr ? write_error : close_error;
    respond_error(call, "decode_failed",
                  error != nullptr ? error->message : "Unreadable image.");
    return;
  }
  GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
  if (pixbuf == nullptr) {
    respond_error(call, "decode_failed", "Unreadable image.");
    return;
  }
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_set_image(clipboard, pixbuf);
  // Lets a clipboard manager keep the image after QuickShare exits.
  gtk_clipboard_set_can_store(clipboard, nullptr, 0);
  g_autoptr(FlValue) ok = fl_value_new_bool(TRUE);
  respond(call, ok);
}

void desktop_channel_present_window(DesktopChannel* self) {
  if (self == nullptr || self->window == nullptr) {
    return;
  }
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_deiconify(self->window);
  gtk_window_present_with_time(self->window, GDK_CURRENT_TIME);
}

static gboolean on_delete_event(GtkWidget* widget, GdkEvent* event,
                                gpointer user_data) {
  DesktopChannel* self = static_cast<DesktopChannel*>(user_data);
  if (!self->close_to_tray) {
    return FALSE;  // Close normally: the application quits.
  }
  gtk_widget_hide(widget);
  fl_method_channel_invoke_method(self->channel, "windowHidden", nullptr,
                                  nullptr, nullptr, nullptr);
  return TRUE;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  DesktopChannel* self = static_cast<DesktopChannel*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "clipboardReadImage") == 0) {
    read_clipboard_image(call);
  } else if (strcmp(method, "clipboardWriteImage") == 0) {
    write_clipboard_image(call, args);
  } else if (strcmp(method, "windowShow") == 0) {
    desktop_channel_present_window(self);
    respond(call, nullptr);
  } else if (strcmp(method, "windowHide") == 0) {
    if (self->window != nullptr) {
      gtk_widget_hide(GTK_WIDGET(self->window));
    }
    respond(call, nullptr);
  } else if (strcmp(method, "windowIsVisible") == 0) {
    g_autoptr(FlValue) visible = fl_value_new_bool(
        self->window != nullptr &&
        gtk_widget_get_visible(GTK_WIDGET(self->window)));
    respond(call, visible);
  } else if (strcmp(method, "setCloseToTray") == 0) {
    self->close_to_tray = args != nullptr &&
                          fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                          fl_value_get_bool(args);
    respond(call, nullptr);
  } else if (strcmp(method, "quit") == 0) {
    self->close_to_tray = FALSE;
    respond(call, nullptr);
    g_application_quit(g_application_get_default());
  } else {
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_not_implemented(call, &error);
  }
}

DesktopChannel* desktop_channel_new(FlView* view, GtkWindow* window) {
  DesktopChannel* self = g_new0(DesktopChannel, 1);
  self->window = window;
  self->close_to_tray = FALSE;
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                            "quickshare/desktop", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);
  self->delete_handler = g_signal_connect(window, "delete-event",
                                          G_CALLBACK(on_delete_event), self);
  // The window can be destroyed before the application is disposed.
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));
  return self;
}

void desktop_channel_free(DesktopChannel* self) {
  if (self == nullptr) {
    return;
  }
  if (self->window != nullptr) {
    g_signal_handler_disconnect(self->window, self->delete_handler);
    g_object_remove_weak_pointer(G_OBJECT(self->window),
                                 reinterpret_cast<gpointer*>(&self->window));
  }
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_clear_object(&self->channel);
  g_free(self);
}
