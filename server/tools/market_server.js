// 독립 모의 주식시장 서버: 게임 서버가 MARKET_FEED_URL 로 1분마다 시세를 읽어 가는 바로 그 형식을 내놓는다.
//   GET /quotes → { ts, minute, quotes: { 종목id: 가격, … } }
// 실제 시세를 쓰고 싶으면 이 파일 대신 같은 형식으로 답하는 다리(증권사 API → { quotes })를 띄우면 된다.
// 사용: node tools/market_server.js [--port 8090] [--tick-ms 60000]
//       게임 서버: MARKET_FEED_URL=http://127.0.0.1:8090/quotes node src/index.js
import http from 'node:http';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { roundToTick, simStep } from '../src/market.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const rules = JSON.parse(readFileSync(path.join(here, '../../data/market/stocks.json'), 'utf8'));
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? Number(process.argv[i + 1]) : fallback;
};
const port = arg('--port', Number(process.env.PORT ?? 8090));
const tickMs = arg('--tick-ms', 60000);

let minute = 0;
const stocks = new Map(rules.stocks.map((d) => [d.id, { price: roundToTick(d.price), ref: d.price }]));
const defs = new Map(rules.stocks.map((d) => [d.id, d]));

setInterval(() => {
  minute += 1;
  for (const [id, s] of stocks) s.price = simStep(s, defs.get(id), rules, Math.random);
}, tickMs);

http
  .createServer((req, res) => {
    if (req.method === 'GET' && (req.url === '/quotes' || req.url === '/')) {
      const quotes = Object.fromEntries([...stocks].map(([id, s]) => [id, s.price]));
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ts: Date.now(), minute, quotes }));
      return;
    }
    res.writeHead(404);
    res.end();
  })
  .listen(port, () => console.log(`[market-server] http://127.0.0.1:${port}/quotes (${tickMs}ms 마다 움직임)`));
