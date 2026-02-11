## RainCity Voice Studio — PRD & Implementation Spec Kit

### 0) Goal
Ship a multi-tenant, Washington-compliant voice-agent runtime that never drops calls: caller containers with persistent memory, canonical append-only logs, explicit consent capture, and issue tracking. Deliver a working vertical slice suitable for home services/clinics in Seattle.

### 1) Scope (vertical slice)
- Inbound voice session flow with tenant_id + inbound_number input.
- Caller container resolution + memory hydrate + append-only event log.
- Consent prompt and recording gate (two-party consent).
- Tool contract surfaces: identity.resolve_caller_container, mem.read_snapshot, mem.search, mem.write_patch, log.append, issues.upsert.
- Open-issue fallback when outcomes aren’t completed.

### 2) Success criteria (acceptance)
- Every session emits ordered canonical events: call_started → consent_* → memory_hydrated → intent_identified → tool_called → booking_* / transfer_* / sms_* → issue_* (if pending) → call_summary_written → call_ended.
- All tool calls include tenant_id + caller_container_id + session_id + correlation_id.
- Recording starts only after consent_granted; consent_denied ends/defers call.
- Memory updates cite event_ids (audit trail). No cross-tenant reads/writes.
- Open issues created when unresolved; include next_action, owner, due_at.

### 3) Non-functional
- Multi-tenant isolation enforced at API/service layer (RLS/RBAC if DB-backed).
- Idempotent log append (event_id uuid); retries safe.
- PII minimized: facts limited to name, phone, address, preferences needed for service.
- Latency target: sub-400ms tool-call overhead budget; streaming STT/TT.

### 4) System prompt (runtime)
Use the provided “RainCity Voice Studio – Voice Agent Runtime” system prompt verbatim (two-layer: caller container + canonical logging + “never drop the ball” checklist). Include mandatory call-start and wrap-up protocols.

### 5) Tool contract (must implement)
- **identity.resolve_caller_container**: {tenant_id, caller_phone, caller_name?, inbound_number?} → {caller_container_id, canonical_contact_id, is_new}
- **mem.read_snapshot**: {tenant_id, caller_container_id} → {facts, issues, preferences, last_updated_at}
- **mem.search**: {tenant_id, caller_container_id, query, time_window_days?} → {results}
- **mem.write_patch**: {tenant_id, caller_container_id, patch, citations:[{session_id, event_id}]} → {ok}
- **log.append**: {tenant_id, caller_container_id, session_id, event_type, payload, actor, correlation_id, request_id?} → {event_id, timestamp}
- **issues.upsert**: {tenant_id, caller_container_id, issue:{title,status,priority,next_action,owner,due_at,notes?,issue_id?}} → {issue_id}

### 6) Data model (reference, Postgres-friendly)
- tenants(id, name, policies, created_at)
- caller_containers(id, tenant_id, canonical_contact_id, primary_phone, metadata, created_at)
- contacts(id, tenant_id, name, phones[], emails[], addresses[], created_at)
- memories(id, tenant_id, caller_container_id, facts jsonb, preferences jsonb, issues jsonb, last_updated_at)
- events(id uuid pk, tenant_id, caller_container_id, session_id, correlation_id, event_type, payload jsonb, actor, request_id, created_at)
- issues(id, tenant_id, caller_container_id, title, status, priority, next_action, owner, due_at, notes, updated_at)

### 7) API surface (BFF / FastAPI or Node)
- POST /api/identity/resolve_caller_container
- POST /api/mem/read_snapshot
- POST /api/mem/search
- POST /api/mem/write_patch
- POST /api/log/append
- POST /api/issues/upsert
Auth: tenant-scoped token; every request requires tenant_id. Enforce RLS/RBAC.

### 8) Voice session flow (happy path)
1. Input: tenant_id, inbound_number, caller_phone; create session_id + correlation_id.
2. log.append call_started.
3. resolve_caller_container; log tool_called + tool_result.
4. mem.read_snapshot + mem.search; log memory_hydrated.
5. If recording enabled, request consent → log consent_requested; on yes log consent_granted; else consent_denied and end.
6. Conversational loop: identify intent, qualify (service, zip, urgency, time window, callback number), propose slots, book via tool; log each tool call/result.
7. If booking fails or caller defers, issues.upsert(open) with next_action + due_at.
8. call_summary_written with problem, actions, tools, outcome, open issues; mem.write_patch with citations; call_ended.

### 9) Compliance (WA two-party)
- Consent line before recording; store consent event + timestamp.
- If no consent, disable recording and continue via SMS/callback or end politely.
- Sensitive data minimized; no cross-tenant access even if phone overlaps.

### 10) Safety & resiliency
- Tool failure: apologize, offer transfer/SMS, issues.upsert(open, owner=human), log tool failure event.
- Rate limits per tenant; alert on abnormal call/tool failure rates.
- Fallback: transfer_to_human or voicemail + SMS follow-up; log transfer_* or sms_* events.

### 11) Dependencies (reference stack)
- STT: Deepgram Nova-3 streaming; TTS: ElevenLabs conversational; LLM orchestration: Claude Sonnet 4.5; classifier/routing: Claude Haiku 4.5.
- Telephony: Twilio inbound webhook → session kickoff (can be swapped with Telnyx).

### 12) Deliverables checklist (for implementing agent)
- [ ] System prompt integrated into runtime.
- [ ] Tool contracts implemented (in-memory first, RLS-ready later).
- [ ] Canonical event schemas and tests for ordering/required fields.
- [ ] Consent gate in session startup; tests for grant/deny.
- [ ] Issue creation on unresolved outcomes.
- [ ] Demo seed: demo tenant + sample caller_container_id + synthetic events.
- [ ] README snippet on env vars and WA consent note.

### 13) Rollout plan (30-day)
- Week 1: In-memory BFF + session wiring + consent gate + logging tests.
- Week 2: Persisted Postgres schema + RLS + migrations; seed demo tenant.
- Week 3: Telephony webhook + SMS follow-up + dashboard stub for events/issues.
- Week 4: Load tests, WA compliance review, pilot with 1–2 home services tenants.
