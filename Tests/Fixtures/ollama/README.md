# Recorded Ollama streams

Synthetic. Hand-written to the shape Ollama's `/api/chat` emits with
`stream: true`, not captured from a real generation, so that contract tests can
run in CI with no daemon and this public repository carries no real text.

`chat-stream.ndjson` -- four content deltas that concatenate to a complete
translate response, then a terminating chunk. Ollama sends empty content on the
`done` chunk; that is reproduced here because `OllamaWire.event(from:)` depends
on it.
