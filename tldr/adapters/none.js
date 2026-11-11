// The adapter that always answers "no model": the reader with its outline and nothing else. The tests
// use it, and it is what a platform with no model path supplies.
(() => {
  const T = globalThis.__tldr ??= {};
  T.adapter = {
    status: async () => ({ model: 'none' }),
    summarize(request, onPiece) { onPiece({ op: 'error', code: 'unavailable' }); return () => {}; },
    classify: async () => [],
  };
})();
