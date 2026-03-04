/**
 * @interplanet/ltx — LTX (Light-Time eXchange) TypeScript SDK
 * Story 33.1
 *
 * Pure TypeScript port of js/ltx-sdk.js — independent of @interplanet/time.
 * Implements the LTX meeting protocol: plan creation, segment computation,
 * URL hash encoding, ICS generation, and REST client.
 *
 * @example
 * ```ts
 * import { createPlan, computeSegments, generateICS, encodeHash } from '@interplanet/ltx';
 *
 * const plan = createPlan({ title: 'Q3 Review', delay: 860, remoteName: 'Mars Hab-01' });
 * const segs = computeSegments(plan);
 * const ics  = generateICS(plan);
 * const hash = encodeHash(plan);  // "#l=eyJ2IjoyLC..."
 * ```
 */

export type {
  SegmentType,
  NodeRole,
  LocationKey,
  SegmentTemplate,
  LtxNode,
  LtxPlan,
  LtxPlanV1,
  LtxSegment,
  CreatePlanOptions,
  NodeUrl,
} from './types.js';

export {
  VERSION,
  SEG_TYPES,
  DEFAULT_QUANTUM,
  DEFAULT_SEGMENTS,
  DEFAULT_API_BASE,
} from './constants.js';

export { createPlan, upgradeConfig }          from './plan.js';
export { computeSegments, totalMin, makePlanId } from './segments.js';
export { encodeHash, decodeHash }             from './encoding.js';
export { buildNodeUrls }                      from './urls.js';
export { generateICS }                        from './ics.js';
export { formatHMS, formatUTC }              from './formatting.js';
export {
  storeSession, getSession, downloadICS, submitFeedback,
} from './rest.js';
export type {
  SessionResponse, GetSessionResponse, FeedbackResponse,
} from './rest.js';

export {
  canonicalJSON,
  generateNIK,
  nikFingerprint,
  isNIKExpired,
  signPlan,
  verifyPlan,
} from './security.js';
export type {
  NIK,
  GenerateNIKResult,
  GenerateNIKOptions,
  CoseSign1,
  SignedPlan,
  VerifyResult,
} from './security.js';

export {
  createSequenceTracker,
  addSeq,
  checkSeq,
} from './sequence.js';
export type {
  SeqCheckResult,
  SequenceTrackerStorage,
  SequenceTracker,
} from './sequence.js';

export { createMerkleLog, verifyTreeHead } from './merkle.js';
export type {
  MerkleAppendResult,
  InclusionProofStep,
  SignedTreeHead,
  MerkleLog,
} from './merkle.js';

export {
  createKeyBundle,
  verifyAndCacheKeys,
  createRevocation,
  applyRevocation,
} from './keydist.js';
export type {
  KeyBundle,
  KeyRevocation,
} from './keydist.js';

export { addBIB, verifyBIB, generateBIBKey } from './bib.js';
export type { BIB, BIBBundle, BIBVerifyResult } from './bib.js';
export { generateSessionKey, encryptWindow, decryptWindow } from './bcb.js';
export type { BCBBundle, DecryptResult } from './bcb.js';

export {
  createEOK,
  createEmergencyOverride,
  verifyEmergencyOverride,
  createCoSig,
  checkMultiAuth,
} from './eok.js';
export type {
  EOKRecord,
  CreateEOKResult,
  CreateEOKOptions,
  EmergencyOverride,
  CoSigBundle,
  MultiAuthResult,
} from './eok.js';

export {
  artefactSha256,
  createWindowManifest,
  verifyWindowManifest,
  hedgedSign,
  hedgedVerify,
} from './manifest.js';
export type {
  Artefact,
  TreeHeadRef,
  WindowManifest,
  HedgedSignResult,
} from './manifest.js';

export {
  createConjunctionCheckpoint,
  verifyConjunctionCheckpoint,
  createPostConjunctionQueue,
  createPostConjunctionClear,
  verifyPostConjunctionClear,
} from './conjunction.js';
export type {
  ConjunctionInfo,
  ConjunctionCheckpoint,
  DrainResult,
  PostConjunctionQueue,
  PostConjunctionClear,
} from './conjunction.js';
