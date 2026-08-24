# Choosing a model for a7a-llm

The board ships with llama.cpp built and ready. It does **not** ship a model —
those are a personal choice and each one is gigabytes. Pick one below, drop it in
`/home/radxa/models`, and it appears in `a7a-llm list` and in the GUI.

```sh
mkdir -p ~/models
cd ~/models
wget <one of the links below>
a7a-llm list          # confirm it is seen
a7a-llm serve         # start the server on :8080
```

## Get the quantisation right — it matters more than usual here

Use **Q4_0**, not Q4_K_M, on this board. llama.cpp repacks Q4_0 into
aarch64 dotprod-interleaved layouts, and this SoC has `asimddp`. Measured on the
A7A: **17.1 tok/s prompt processing on Q4_0 versus 7.5 on Q4_K_M** — about 2.3×,
at the same generation speed. A K-quant looks like the smarter choice on paper
and is the wrong one here.

## Recommended models

| model | file | size | why |
|---|---|---|---|
| **Qwen3 4B Instruct** | `Qwen3-4B-Instruct-2507-Q4_0.gguf` | ~2.4 GB | the default — comfortable on 12 GB with a desktop running |
| **Ling-mini 2.0** | `inclusionAI_Ling-mini-2.0-Q4_0.gguf` | ~9.0 GB | nearly 2× faster (6.63 vs 3.33 tok/s) — **headless only**, see the warning |
| **Qwen3 1.7B** | `Qwen3-1.7B-Q4_0.gguf` | ~1.1 GB | fastest, lightest, good for quick tasks |
| **Gemma 3 4B** | `gemma-3-4b-it-Q4_0.gguf` | ~2.5 GB | strong general alternative to Qwen3 4B |

Search Hugging Face for these filenames — most are published by
[bartowski](https://huggingface.co/bartowski) or
[unsloth](https://huggingface.co/unsloth) in GGUF form. Prefer a repository that
publishes a real `Q4_0` file rather than only K-quants.

> ### ⚠️ About Ling-mini 2.0
>
> It is a 16B mixture-of-experts model that reads only ~1.43B parameters per
> token, which is why it is fast. But it is **9.0 GB on a 12 GB board with no
> swap**. It locked the board up twice with a desktop session running. Use it
> headless, or stop the desktop first:
>
> ```sh
> sudo systemctl stop lightdm
> A7A_LLM_MODEL=inclusionAI_Ling-mini-2.0-Q4_0.gguf a7a-llm serve
> ```

## Speed on this board, and why

Generation is limited by the **two A76 cores**, not memory bandwidth — the DRAM
bus peaks at 16.4 GB/s and llama.cpp only reaches about 7.2. So `a7a-llm` uses
settings that look wrong and are not:

* **Generation: 2 threads.** Using all eight measured **35% slower** (3.12 → 2.04
  tok/s on a 4B model), because ggml splits work evenly and the six A55 cores
  stall the per-layer barrier.
* **Prompt processing: 8 threads.** That part is compute-bound and scales fine.

llama.cpp supports both at once — `-t` for generation, `-tb` for batch — and
`a7a-llm` sets them for you.

The CPU governor also matters, a lot. The default `schedutil` leaves the A76 pair
idling near 1612 MHz instead of 3000. `a7a-llm` pins it to `performance` while
the server runs and restores it on exit.

## Overriding the defaults

| variable | default | purpose |
|---|---|---|
| `A7A_LLM_MODELS` | `/home/radxa/models` | where models live |
| `A7A_LLM_MODEL` | `Qwen3-4B-Instruct-2507-Q4_0.gguf` | which one to serve |
| `A7A_LLM_BIN` | packaged llama.cpp | use your own build instead |
| `A7A_LLM_PORT` | `8080` | server port |
| `A7A_LLM_CTX` | `4096` | context size |
| `A7A_LLM_THREADS` | `2` | generation threads |
| `A7A_LLM_THREADS_BATCH` | `8` | prompt threads |

The server is OpenAI-compatible, so anything that talks to that API works
against `http://<board>:8080`.
