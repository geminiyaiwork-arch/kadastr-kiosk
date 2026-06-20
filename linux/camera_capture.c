// Kiosk kamera-suratga-oluvchi (Linux) — WebKitGTK + getUserMedia.
//
// Flutter'нинг `camera` paketi Linux desktop'ни qo'llab-quvvatlamaydi. Lekin
// WebKitGTK kamerага kira oladi. Bu helper fullscreen kamera oynasини ochadi,
// foydalanuvchi "Suratga olish"ни bossa yuz rasmini base64 (JPEG) qilib
// argv[1] faylга yozadi va yopiladi. ESC → bekor (fayl yozilmaydi).
//
// Build:
//   gcc camera_capture.c -o myid-camera \
//       $(pkg-config --cflags --libs gtk+-3.0 webkit2gtk-4.1) -ljavascriptcoregtk-4.1
//
// Ishlatish: ./myid-camera /tmp/face.txt   → fayl ichida "data:image/jpeg;base64,..."

#include <gtk/gtk.h>
#include <gdk/gdkkeysyms.h>
#include <webkit2/webkit2.h>
#include <jsc/jsc.h>
#include <stdio.h>

static char *g_out = NULL;

static const char *HTML =
  "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
  "<style>html,body{margin:0;height:100%;background:#0c1430;font-family:system-ui,sans-serif;overflow:hidden}"
  "#v{position:fixed;inset:0;width:100vw;height:100vh;object-fit:cover;transform:scaleX(-1)}"
  "#st{position:fixed;top:24px;left:0;right:0;text-align:center;color:#fff;font-size:30px;font-weight:600;text-shadow:0 2px 8px #000;z-index:2}"
  "#oval{position:fixed;left:50%;top:46%;width:340px;height:430px;transform:translate(-50%,-50%);border:4px solid #fff;border-radius:50%;box-shadow:0 0 0 4000px rgba(8,16,40,.45);z-index:1}"
  "#btns{position:fixed;bottom:40px;left:0;right:0;display:flex;gap:18px;justify-content:center;z-index:3}"
  "button{font-size:26px;font-weight:700;padding:20px 44px;border:0;border-radius:18px;color:#fff;cursor:pointer}"
  ".cap{background:#1FA463}.can{background:#334;}</style></head>"
  "<body><video id='v' autoplay playsinline muted></video><div id='oval'></div>"
  "<div id='st'>Yuzingizni doira ichida ushlang</div>"
  "<div id='btns'><button class='cap' id='cap'>\xF0\x9F\x93\xB8 Suratga olish</button>"
  "<button class='can' id='can'>Bekor</button></div>"
  "<script>"
  "const v=document.getElementById('v'),st=document.getElementById('st');"
  "function send(m){try{window.webkit.messageHandlers.photo.postMessage(m);}catch(e){}}"
  "navigator.mediaDevices.getUserMedia({video:{facingMode:'user',width:{ideal:1280},height:{ideal:720}},audio:false})"
  ".then(s=>{v.srcObject=s;}).catch(e=>{st.textContent='Kamera ochilmadi: '+e;});"
  "function shoot(){const c=document.createElement('canvas');c.width=v.videoWidth||1280;c.height=v.videoHeight||720;"
  "const x=c.getContext('2d');x.drawImage(v,0,0,c.width,c.height);"
  "send(c.toDataURL('image/jpeg',0.92));}"
  "document.getElementById('cap').onclick=shoot;"
  "document.getElementById('can').onclick=()=>send('CANCEL');"
  "document.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' ')shoot();if(e.key==='Escape')send('CANCEL');});"
  "</script></body></html>";

static void on_script_msg(WebKitUserContentManager *m, WebKitJavascriptResult *r, gpointer data) {
  (void)m; (void)data;
  JSCValue *val = webkit_javascript_result_get_js_value(r);
  char *str = jsc_value_to_string(val);
  if (str && g_out && str[0] != 'C') {            // "CANCEL" bo'lmasa yozamiz
    FILE *f = fopen(g_out, "w");
    if (f) { fputs(str, f); fclose(f); }
  }
  if (str) g_free(str);
  gtk_main_quit();
}

static gboolean on_permission(WebKitWebView *web, WebKitPermissionRequest *req, gpointer data) {
  (void)web; (void)data;
  webkit_permission_request_allow(req);
  return TRUE;
}

static gboolean on_key(GtkWidget *w, GdkEventKey *e, gpointer data) {
  (void)w; (void)data;
  if (e->keyval == GDK_KEY_Escape) { gtk_main_quit(); return TRUE; }
  return FALSE;
}

int main(int argc, char **argv) {
  gtk_init(&argc, &argv);
  g_out = (argc > 1) ? argv[1] : NULL;

  GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(win), "MyID — yuzni suratga olish");
  gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
  gtk_window_fullscreen(GTK_WINDOW(win));
  g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);
  g_signal_connect(win, "key-press-event", G_CALLBACK(on_key), NULL);

  WebKitUserContentManager *ucm = webkit_user_content_manager_new();
  webkit_user_content_manager_register_script_message_handler(ucm, "photo");
  g_signal_connect(ucm, "script-message-received::photo", G_CALLBACK(on_script_msg), NULL);

  WebKitWebView *web = WEBKIT_WEB_VIEW(webkit_web_view_new_with_user_content_manager(ucm));
  WebKitSettings *s = webkit_web_view_get_settings(web);
  webkit_settings_set_enable_media_stream(s, TRUE);
  webkit_settings_set_enable_webgl(s, TRUE);
  webkit_settings_set_media_playback_requires_user_gesture(s, FALSE);

  g_signal_connect(web, "permission-request", G_CALLBACK(on_permission), NULL);
  gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(web));
  webkit_web_view_load_html(web, HTML, "https://kadastr.local/");
  gtk_widget_show_all(win);
  gtk_main();
  return 0;
}
