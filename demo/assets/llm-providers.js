/**
 * llm-providers.js — LLM Provider Registry
 * ─────────────────────────────────────────
 * Defines available AI provider endpoints, model lists, and auth schemes.
 * Kept as a standalone file so model lists and base URLs can be updated
 * independently of the main application logic (sky.js).
 *
 * Auth schemes:
 *   bearer    — Authorization: Bearer <key>  (OpenAI-compatible)
 *   api-key   — api-key: <key> header        (Azure, Gemini)
 *   anthropic — x-api-key + anthropic-version headers
 *   none      — no auth (local/Ollama)
 *
 * To add a new provider: add an entry below and optionally a streaming
 * adapter in sky.js (_streamOpenAiCompat handles the common case).
 *
 * Last updated: 2026-02-27
 */

/* global window */

window.LLM_PROVIDERS = {
  openai: {
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-4-turbo-preview',
      'gpt-3.5-turbo',
      'o1',
      'o1-mini',
      'o3-mini',
    ],
    auth: 'bearer',
  },

  anthropic: {
    name: 'Anthropic',
    baseUrl: 'https://api.anthropic.com',
    models: [
      'claude-opus-4-6',
      'claude-sonnet-4-6',
      'claude-haiku-4-5-20251001',
    ],
    auth: 'anthropic',
  },

  gemini: {
    name: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    models: [
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
    ],
    auth: 'api-key',
  },

  mistral: {
    name: 'Mistral',
    baseUrl: 'https://api.mistral.ai/v1',
    models: [
      'mistral-large-latest',
      'mistral-medium-latest',
      'mistral-small-latest',
      'open-mistral-7b',
      'open-mixtral-8x7b',
    ],
    auth: 'bearer',
  },

  groq: {
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    models: [
      'llama-3.3-70b-versatile',
      'llama-3.1-70b-versatile',
      'llama-3.1-8b-instant',
      'gemma2-9b-it',
      'deepseek-r1-distill-llama-70b',
    ],
    auth: 'bearer',
  },

  together: {
    name: 'Together AI',
    baseUrl: 'https://api.together.xyz/v1',
    models: [
      'meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo',
      'meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo',
      'mistralai/Mixtral-8x7B-Instruct-v0.1',
      'deepseek-ai/deepseek-r1',
    ],
    auth: 'bearer',
  },

  perplexity: {
    name: 'Perplexity',
    baseUrl: 'https://api.perplexity.ai',
    models: [
      'sonar-pro',
      'sonar',
      'sonar-reasoning-pro',
      'sonar-reasoning',
      'r1-1776',
    ],
    auth: 'bearer',
  },

  cohere: {
    name: 'Cohere',
    baseUrl: 'https://api.cohere.com/compatibility/v1',
    models: [
      'command-r-plus',
      'command-r',
      'command-r-plus-08-2024',
    ],
    auth: 'bearer',
  },

  xai: {
    name: 'xAI Grok',
    baseUrl: 'https://api.x.ai/v1',
    models: [
      'grok-2',
      'grok-2-mini',
      'grok-beta',
    ],
    auth: 'bearer',
  },

  deepseek: {
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    models: [
      'deepseek-chat',
      'deepseek-reasoner',
    ],
    auth: 'bearer',
  },

  azure: {
    name: 'Azure OpenAI',
    // Base URL format: https://<resource>.openai.azure.com/openai/deployments/<deployment>
    // Set via the base URL override field
    baseUrl: '',
    models: [],
    auth: 'api-key',
    note: 'Set base URL to your Azure endpoint. Model field = deployment name.',
  },

  ollama: {
    name: 'Ollama (local)',
    baseUrl: 'http://localhost:11434/v1',
    models: [
      'llama3.2',
      'llama3.1',
      'mistral',
      'phi4',
      'phi3',
      'qwen2.5',
      'deepseek-r1',
      'gemma3',
    ],
    auth: 'none',
  },
};
