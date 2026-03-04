/**
 * @interplanet/ltx — REST API client
 */

import { DEFAULT_API_BASE } from './constants.js';
import type { LtxPlan, LtxPlanV1 } from './types.js';

export interface SessionResponse {
  plan_id:    string;
  segments:   object[];
  total_min:  number;
  stored:     boolean;
}

export interface GetSessionResponse {
  plan_id:    string;
  plan:       LtxPlan;
  created_at: string;
  views:      number;
}

export interface FeedbackResponse {
  ok:          boolean;
  feedback_id: number;
}

/**
 * Store a session plan on the server.
 */
export async function storeSession(
  cfg: LtxPlan | LtxPlanV1,
  apiBase?: string,
): Promise<SessionResponse> {
  const url  = apiBase || DEFAULT_API_BASE;
  const resp = await fetch(`${url}?action=session`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(cfg),
  });
  if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
  return resp.json() as Promise<SessionResponse>;
}

/**
 * Retrieve a stored session plan by plan ID.
 */
export async function getSession(
  planId: string,
  apiBase?: string,
): Promise<GetSessionResponse> {
  const url  = apiBase || DEFAULT_API_BASE;
  const resp = await fetch(`${url}?action=session&plan_id=${encodeURIComponent(planId)}`);
  if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
  return resp.json() as Promise<GetSessionResponse>;
}

/**
 * Download ICS content for a stored plan.
 */
export async function downloadICS(
  planId:  string,
  opts:    { start: string; duration_min: number },
  apiBase?: string,
): Promise<string> {
  const url  = apiBase || DEFAULT_API_BASE;
  const resp = await fetch(`${url}?action=ics&plan_id=${encodeURIComponent(planId)}`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(opts),
  });
  if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
  return resp.text();
}

/**
 * Submit session feedback.
 */
export async function submitFeedback(
  payload:  object,
  apiBase?: string,
): Promise<FeedbackResponse> {
  const url  = apiBase || DEFAULT_API_BASE;
  const resp = await fetch(`${url}?action=feedback`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(payload),
  });
  if (!resp.ok) throw new Error(`LTX API ${resp.status}: ${await resp.text()}`);
  return resp.json() as Promise<FeedbackResponse>;
}
