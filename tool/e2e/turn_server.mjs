// Local TURN server for testing the relay fallback (forced with iceTransportPolicy=relay).
//   node tool/e2e/turn_server.mjs [port]
import Turn from 'node-turn';

const port = Number(process.argv[2] || 3478);
const server = new Turn({
  authMech: 'long-term',
  credentials: { e2e: 'e2e-secret' },
  realm: 'quickshare-e2e',
  listeningPort: port,
  listeningIps: ['127.0.0.1'],
  relayIps: ['127.0.0.1'],
  debugLevel: 'OFF',
});
server.start();
console.log(`TURN listening on 127.0.0.1:${port} (user e2e / e2e-secret)`);
