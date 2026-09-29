#!/usr/bin/env python3
"""ALOMAT wake-word sidecar (Windows/Linux). Mikrofonni tinglaydi (16 kHz), openWakeWord ONNX modeli bilan
"Alomat"ni topadi va localhost WebSocket (ws://127.0.0.1:8765) orqali kioskga {"event":"wake","score":0.93} yuboradi.
Ishga tushirish: alomat_wake.exe --model alomat.onnx --threshold 0.7 [--device N] [--port 8765]"""
import argparse, asyncio, json, os, sys, time, threading, queue
import numpy as np
try:
    import sounddevice as sd
except Exception as e:
    print('sounddevice yo\'q:', e); sys.exit(2)
try:
    import websockets
except Exception as e:
    print('websockets yo\'q:', e); sys.exit(2)
from openwakeword.model import Model

ap = argparse.ArgumentParser()
ap.add_argument('--model', default=os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'alomat.onnx'))
ap.add_argument('--threshold', type=float, default=0.85)
ap.add_argument('--patience', type=int, default=2, help='ketma-ket shuncha 80 ms bo\'lakda chegaradan yuqori bo\'lsa uyg\'onadi (soxta uyg\'onish kamayadi)')
ap.add_argument('--port', type=int, default=8765)
ap.add_argument('--device', type=int, default=None)
ap.add_argument('--cooldown', type=float, default=2.0, help='bir uyg\'onishdan keyin shuncha soniya jim')
ap.add_argument('--debug', action='store_true')
args = ap.parse_args()

clients = set()
loop = asyncio.new_event_loop()
q = queue.Queue()
model = Model(wakeword_models=[args.model], inference_framework='onnx')
name = list(model.models.keys())[0]
print('model:', name, '| threshold', args.threshold, '| port', args.port, flush=True)

last_fire = 0.0
above = 0
def audio_cb(indata, frames, t, status):
    global last_fire, above
    pcm = (indata[:, 0] * 32767).astype(np.int16) if indata.dtype != np.int16 else indata[:, 0]
    score = float(model.predict(pcm)[name])
    now = time.time()
    if args.debug and score > 0.2: print('score %.2f' % score, flush=True)
    above = above + 1 if score >= args.threshold else 0
    if above >= args.patience and now - last_fire > args.cooldown:
        last_fire = now; above = 0
        model.reset()
        q.put({'event': 'wake', 'score': round(score, 3), 'ts': now})
        print('WAKE %.2f' % score, flush=True)

async def handler(ws):
    clients.add(ws)
    try:
        await ws.send(json.dumps({'event': 'hello', 'model': name, 'threshold': args.threshold}))
        async for _ in ws:
            pass
    finally:
        clients.discard(ws)

async def pump():
    while True:
        try:
            ev = q.get_nowait()
        except queue.Empty:
            await asyncio.sleep(0.02); continue
        dead = []
        for ws in list(clients):
            try: await ws.send(json.dumps(ev))
            except Exception: dead.append(ws)
        for ws in dead: clients.discard(ws)

async def main():
    async with websockets.serve(handler, '127.0.0.1', args.port):
        print('ws://127.0.0.1:%d tayyor' % args.port, flush=True)
        await pump()

def audio_thread():
    while True:
        try:
            with sd.InputStream(samplerate=16000, channels=1, dtype='int16', blocksize=1280, device=args.device, callback=audio_cb):
                print('mikrofon ochiq (device=%s)' % (args.device if args.device is not None else 'default'), flush=True)
                while True: time.sleep(1)
        except Exception as e:
            print('mikrofon xatosi:', e, '— 3 s dan keyin qayta', flush=True); time.sleep(3)

threading.Thread(target=audio_thread, daemon=True).start()
try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
