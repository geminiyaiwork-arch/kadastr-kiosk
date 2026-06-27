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
  "#oval{position:fixed;left:50%;top:46%;width:340px;height:430px;transform:translate(-50%,-50%);border:5px solid #fff;border-radius:50%;box-shadow:0 0 0 4000px rgba(8,16,40,.45);z-index:1;transition:border-color .2s}"
  "#oval.ok{border-color:#1FA463}"
  "#btns{position:fixed;bottom:40px;left:0;right:0;display:flex;gap:18px;justify-content:center;z-index:3}"
  "button{font-size:26px;font-weight:700;padding:20px 44px;border:0;border-radius:18px;color:#fff;cursor:pointer}"
  ".cap{background:#1FA463}.can{background:#334;}</style></head>"
  "<body><video id='v' autoplay playsinline muted></video><div id='oval'></div>"
  "<div id='st'>Yuzingizni doira ichida ushlang</div>"
  "<div id='btns'><button class='cap' id='cap'>\xF0\x9F\x93\xB8 Hozir olish</button>"
  "<button class='can' id='can'>Bekor</button></div>"
  "<script>"
  "const v=document.getElementById('v'),st=document.getElementById('st'),oval=document.getElementById('oval');"
  "let done=false,hits=0,cd=0;"
  "function send(m){try{window.webkit.messageHandlers.photo.postMessage(m);}catch(e){}}"
  "navigator.mediaDevices.getUserMedia({video:{facingMode:'user',width:{ideal:1280},height:{ideal:720},frameRate:{ideal:24,max:30}},audio:false})"
  ".then(s=>{v.srcObject=s;v.onloadeddata=()=>setTimeout(loop,400);})"
  ".catch(e=>{st.textContent='Kamera ochilmadi: '+e;});"
  "function shoot(){if(done)return;done=true;st.textContent='Suratga olinmoqda...';"
  "const c=document.createElement('canvas');c.width=v.videoWidth||1280;c.height=v.videoHeight||720;"
  "const x=c.getContext('2d');x.drawImage(v,0,0,c.width,c.height);"
  "send(c.toDataURL('image/jpeg',0.92));}"
  // yuz doirада bormi — qo'pol AI: markaz hududда yetarli yorug'lik + detal (variansiya)
  "const tc=document.createElement('canvas');tc.width=64;tc.height=80;const tx=tc.getContext('2d');"
  "function faceish(){const vw=v.videoWidth,vh=v.videoHeight;if(!vw)return false;"
  "tx.drawImage(v,vw*0.30,vh*0.12,vw*0.40,vh*0.62,0,0,64,80);"
  "const d=tx.getImageData(0,0,64,80).data;let s=0,s2=0,n=64*80;"
  "for(let i=0;i<d.length;i+=4){const l=d[i]*0.3+d[i+1]*0.59+d[i+2]*0.11;s+=l;s2+=l*l;}"
  "const m=s/n,varr=s2/n-m*m;return m>45&&m<235&&varr>260;}"
  // avto-aniqlash sikli: yuz barqaror bo'lsa countdown → o'zи suratga oladi
  "function loop(){if(done)return;const ok=faceish();oval.classList.toggle('ok',ok);"
  "if(ok){hits++;}else{hits=0;cd=0;st.textContent='Yuzingizni doira ichida ushlang';}"
  "if(hits>=3){countdown();return;}setTimeout(loop,400);}"
  "function countdown(){if(done)return;if(!faceish()){hits=0;cd=0;oval.classList.remove('ok');setTimeout(loop,300);return;}"
  "if(cd===0)cd=3;st.textContent='Tayyor! Qimirламанг... '+cd;cd--;"
  "if(cd<0){shoot();}else{setTimeout(countdown,800);}}"
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
