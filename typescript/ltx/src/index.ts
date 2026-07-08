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
  LtxPlanV3,
  AnyLtxPlan,
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
  DELAY_VIOLATION_WARN_S,
  DELAY_VIOLATION_DEGRADE_S,
  LOCK_TIMEOUT_FACTOR,
} from './constants.js';

export { createSession, transition, lockTimeoutMs } from './session.js';
export type {
  SessionState,
  SessionEvent,
  SessionEffect,
  SessionContext,
  SessionOptions,
  StateTransitionEntry,
  PendingAmendment,
  TransitionResult,
  LockKind,
} from './session.js';

export {
  planHash,
  createAmendment,
  verifyAmendmentChain,
  insertBufferViaAmendment,
} from './amend.js';

export {
  createRegisterEntry,
  verifyRegisterEntry,
  compareEntries,
  orderEntries,
  reduceQuestions,
  reduceActions,
  emitQuestionSeeds,
} from './registers.js';
export type {
  RegisterEntryType,
  RegisterEntry,
  CreateEntryOptions,
  EntryVerifyResult,
  QuestionState,
  ActionState,
  RegisterReduction,
} from './registers.js';

export {
  mergeLogs,
  entriesRoot,
  runMergeSegment,
  recoverPartition,
} from './merge.js';
export type {
  MergeResult,
  PartitionOutcome,
} from './merge.js';

export { createPlan, upgradeConfig, upgradePlanToV3 } from './plan.js';
export {
  computeSegments, computeSegmentsFor, pairDelay, totalMin, makePlanId,
} from './segments.js';
export type { LtxViewerSegment } from './segments.js';
export { encodeHash, decodeHash }             from './encoding.js';
export { buildNodeUrls }                      from './urls.js';
export { generateICS }                        from './ics.js';
export type { GenerateICSOptions }            from './ics.js';
export { buildConferenceAgenda, primeTimeReport } from './conference.js';
export type { ConferenceAgendaOptions, PrimeTimeEntry } from './conference.js';
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
  createGlobalSequenceTracker,
  checkIssuedAt,
  ISSUED_AT_MAX_AGE_DAYS,
  addSeq,
  checkSeq,
} from './sequence.js';
export type {
  SeqCheckResult,
  SequenceTrackerStorage,
  SequenceTracker,
  GlobalSequenceTracker,
} from './sequence.js';

export { encodeCbor, decodeCbor, CborTag } from './cbor.js';

export {
  signPlanCose,
  verifyPlanCose,
  verifyPlanAny,
  COSE_SIGN1_TAG,
  COSE_ALG_ED25519,
} from './cose.js';
export type { CoseSignedPlan } from './cose.js';

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

export {
  addBIB, verifyBIB, generateBIBKey,
  addBIBEd25519, verifyBIBEd25519,
} from './bib.js';
export type { BIB, BIBEd25519, BIBBundle, BIBVerifyResult } from './bib.js';
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
