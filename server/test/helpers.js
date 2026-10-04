import { randomBytes } from 'node:crypto';
import { WebSocket } from 'ws';

export const uid = () => randomBytes(8).toString('hex');

export class Client {
  constructor(port) {
    this.ws = new WebSocket(`ws://127.0.0.1:${port}`);
    this.inbox = [];
    this.waiters = [];
    this.closed = null;
    this.ws.on('message', (d) => {
      const m = JSON.parse(d.toString());
      const i = this.waiters.findIndex((w) => w.pred(m));
      if (i >= 0) this.waiters.splice(i, 1)[0].resolve(m);
      else this.inbox.push(m);
    });
    this.ws.on('close', (code) => {
      this.closed = code;
    });
    this.opened = new Promise((r) => this.ws.on('open', r));
  }
  send(m) {
    this.ws.send(JSON.stringify(m));
  }
  next(pred, ms = 1500) {
    const i = this.inbox.findIndex(pred);
    if (i >= 0) return Promise.resolve(this.inbox.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const w = { pred, resolve };
      this.waiters.push(w);
      setTimeout(() => {
        const j = this.waiters.indexOf(w);
        if (j >= 0) {
          this.waiters.splice(j, 1);
          reject(new Error('timeout waiting for message'));
        }
      }, ms);
    });
  }
  type(t, ms) {
    return this.next((m) => m.t === t, ms);
  }
  kill() {
    this.ws.terminate();
  }
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

