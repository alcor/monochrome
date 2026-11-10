// The reader's adapter in Chrome and Safari: model requests go over a port to the service worker
// (tldr-background.js), which passes them to the Monochrome app. The pieces that come back are the
// `tldr` messages of docs/tldr.md, "The bridge protocol", with the envelope removed.
(() => {
  const T = globalThis.__tldr ??= {};
  let port = null, next = 1;
  const waiting = new Map(); // request id -> onPiece

  function connect() {
    if (port) return port;
    port = chrome.runtime.connect({ name: 'tldr' });
    port.onMessage.addListener(piece => waiting.get(piece.id)?.(piece));
    port.onDisconnect.addListener(() => {
      port = null;
      for (const [id, onPiece] of [...waiting]) { waiting.delete(id); onPiece({ op: 'error', id, code: 'unavailable' }); }
    });
    return port;
  }

  const post = msg => { try { connect().postMessage(msg); return true; } catch { port = null; return false; } };

  T.adapter = {
    status: () => new Promise(resolve => {
      const id = next++;
      const none = { model: 'none', reason: 'noApp' };
      const timer = setTimeout(() => { waiting.delete(id); resolve(none); }, 3000);
      waiting.set(id, piece => {
        clearTimeout(timer);
        waiting.delete(id);
        resolve(piece.op === 'status' ? { model: piece.model, contextSize: piece.contextSize, reason: piece.reason } : none);
      });
      if (!post({ op: 'status', id })) { clearTimeout(timer); waiting.delete(id); resolve(none); }
    }),
    summarize(request, onPiece) {
      const id = next++;
      waiting.set(id, piece => {
        if (piece.op === 'done' || piece.op === 'error') waiting.delete(id);
        onPiece(piece);
      });
      if (!post({ op: 'summarize', id, ...request })) { waiting.delete(id); onPiece({ op: 'error', id, code: 'unavailable' }); }
      return () => { if (waiting.delete(id)) post({ op: 'cancel', id }); };
    },
    classify: async () => [], // the classifier is a later phase
  };
})();
