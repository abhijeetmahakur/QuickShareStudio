#ifndef RUNNER_DESKTOP_CHANNEL_H_
#define RUNNER_DESKTOP_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The "quickshare/desktop" method channel: what Flutter's Linux embedder does not
// provide itself (clipboard images, showing/hiding the window for the system tray).
// GTK talks to X11 and Wayland alike, so nothing here depends on the session type.
typedef struct _DesktopChannel DesktopChannel;

DesktopChannel* desktop_channel_new(FlView* view, GtkWindow* window);

// Shows the window (also when it is hidden in the tray) and raises it.
void desktop_channel_present_window(DesktopChannel* self);

void desktop_channel_free(DesktopChannel* self);

#endif  // RUNNER_DESKTOP_CHANNEL_H_
