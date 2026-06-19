// MyID kamera-yuz uchun WebKitGTK helper (Linux).
//
// Kiosk (Flutter) buni ichki ravishda ishga tushiradi: fullscreen WebKit oynasi
// MyID web sahifasini (signin.devmyid.uz) ochadi, KAMERA ruxsatini avtomatik
// beradi (getUserMedia → yuz tasdiqlash), va redirect (/myid/callback) yuklanib
// bo'lgach o'zini yopadi. So'ng kiosk natijani backend'dan polllaydi.
//
// Build:
//   gcc myid_webview.c -o myid-webview \
//       $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1)
//
// Ishlatish: ./myid-webview "<URL>" "<close-marker>"
//   <close-marker> URL ichida uchrasa (masalan "/myid/callback") oyna yopiladi.

#include <gtk/gtk.h>
#include <gdk/gdkkeysyms.h>
#include <webkit2/webkit2.h>
#include <string.h>

static const char *g_marker = "/myid/callback";

// Har qanday ruxsat so'rovini (kamera/mikrofon) avtomatik beramiz.
static gboolean on_permission(WebKitWebView *web, WebKitPermissionRequest *req, gpointer data) {
  (void)web; (void)data;
  webkit_permission_request_allow(req);
  return TRUE;
}

static gboolean do_quit(gpointer data) { (void)data; gtk_main_quit(); return G_SOURCE_REMOVE; }

// Redirect (callback) sahifasi TO'LIQ yuklangach yopamiz — shunda backend
// auth_code/code almashinuvini tugatib ulguradi.
static void on_load_changed(WebKitWebView *web, WebKitLoadEvent ev, gpointer data) {
  (void)data;
  if (ev != WEBKIT_LOAD_FINISHED) return;
  const char *uri = webkit_web_view_get_uri(web);
  if (uri && g_marker && strstr(uri, g_marker)) {
    g_timeout_add(900, do_quit, NULL);
  }
}

// ESC → bekor qilish.
static gboolean on_key(GtkWidget *w, GdkEventKey *e, gpointer data) {
  (void)w; (void)data;
  if (e->keyval == GDK_KEY_Escape) { gtk_main_quit(); return TRUE; }
  return FALSE;
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);
  const char *url = (argc > 1) ? argv[1] : "about:blank";
  if (argc > 2 && argv[2][0]) g_marker = argv[2];

  GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(win), "MyID — tasdiqlash");
  gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
  gtk_window_fullscreen(GTK_WINDOW(win));
  g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);
  g_signal_connect(win, "key-press-event", G_CALLBACK(on_key), NULL);

  WebKitWebView *web = WEBKIT_WEB_VIEW(webkit_web_view_new());
  WebKitSettings *s = webkit_web_view_get_settings(web);
  webkit_settings_set_enable_media_stream(s, TRUE);          // getUserMedia (kamera)
  webkit_settings_set_enable_webrtc(s, TRUE);
  webkit_settings_set_enable_webgl(s, TRUE);
  webkit_settings_set_media_playback_requires_user_gesture(s, FALSE);
  webkit_settings_set_javascript_can_access_clipboard(s, TRUE);

  g_signal_connect(web, "permission-request", G_CALLBACK(on_permission), NULL);
  g_signal_connect(web, "load-changed", G_CALLBACK(on_load_changed), NULL);

  gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(web));
  webkit_web_view_load_uri(web, url);
  gtk_widget_show_all(win);
  gtk_main();
  return 0;
}
