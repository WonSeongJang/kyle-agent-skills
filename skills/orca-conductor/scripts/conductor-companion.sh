#!/bin/bash
# 프로젝트 supervisor pane에 붙은 mailbox consumer다. 화면 의미 판정은 relay가 맡고,
# companion은 구조화된 relay 후보와 공식 project Run 장부만 대조한다.
set -u

usage() {
  echo "usage: conductor-companion.sh --project <project> --board <board> --supervisor-role <role> --relay-role <role> --run <project-run> [--super-run <legacy-super-run>] [--relay-log <path>] [kicker-interval-sec]" >&2
  exit 2
}
PROJECT=""
BOARD=""
SUPERVISOR_ROLE=""
RELAY_ROLE=""
PROJECT_RUN_ID="${COMPANION_RUN_ID:-}"
SUPER_RUN_ID="${COMPANION_SUPER_RUN_ID:-}"
RELAY_LOG_FILE="${RELAY_LOG_FILE:-}"
KICKER_INTERVAL=300
POSITIONAL_COUNT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || usage; PROJECT="$2"; shift 2 ;;
    --board) [ $# -ge 2 ] || usage; BOARD="$2"; shift 2 ;;
    --supervisor-role) [ $# -ge 2 ] || usage; SUPERVISOR_ROLE="$2"; shift 2 ;;
    --relay-role) [ $# -ge 2 ] || usage; RELAY_ROLE="$2"; shift 2 ;;
    --run) [ $# -ge 2 ] || usage; PROJECT_RUN_ID="$2"; shift 2 ;;
    --super-run) [ $# -ge 2 ] || usage; SUPER_RUN_ID="$2"; shift 2 ;;
    --relay-log) [ $# -ge 2 ] || usage; RELAY_LOG_FILE="$2"; shift 2 ;;
    --*) echo "UNKNOWN_FLAG $1" >&2; usage ;;
    *)
      POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
      [ "$POSITIONAL_COUNT" -eq 1 ] || {
        echo "LEGACY_HANDLE_ARGS_REJECTED use role identity and Run IDs" >&2
        usage
      }
      KICKER_INTERVAL="$1"
      shift
      ;;
  esac
done
[ -n "$PROJECT" ] || { echo "ROLE_IDENTITY_REQUIRED project" >&2; usage; }
[ -n "$BOARD" ] || { echo "ROLE_IDENTITY_REQUIRED board" >&2; usage; }
[ -n "$SUPERVISOR_ROLE" ] || { echo "ROLE_IDENTITY_REQUIRED supervisor-role" >&2; usage; }
[ -n "$RELAY_ROLE" ] || { echo "ROLE_IDENTITY_REQUIRED relay-role" >&2; usage; }
[ -n "$PROJECT_RUN_ID" ] || { echo "COMPANION_RUN_ID_REQUIRED" >&2; exit 2; }

POLL_INTERVAL="${COMPANION_POLL_INTERVAL_SEC:-30}"
LEDGER_SCAN_LIMIT="${PROJECT_LEDGER_SCAN_LIMIT:-100}"
REQUESTED_ORCA_BIN="${ORCA_BIN:-}"
if [ -n "$REQUESTED_ORCA_BIN" ] && [ -x "$REQUESTED_ORCA_BIN" ]; then
  ORCA_BIN="$REQUESTED_ORCA_BIN"
elif [ -n "$REQUESTED_ORCA_BIN" ]; then
  ORCA_BIN=$(command -v "$REQUESTED_ORCA_BIN" 2>/dev/null || true)
elif command -v orca >/dev/null 2>&1; then
  ORCA_BIN=$(command -v orca)
elif [ -x /usr/local/bin/orca ]; then
  ORCA_BIN=/usr/local/bin/orca
elif [ -x /opt/homebrew/bin/orca ]; then
  ORCA_BIN=/opt/homebrew/bin/orca
else
  ORCA_BIN=""
fi
if [ -z "$ORCA_BIN" ] || [ ! -x "$ORCA_BIN" ]; then
  echo "ORCA_BIN_UNAVAILABLE requested=${REQUESTED_ORCA_BIN:-auto}" >&2
  exit 3
fi

DEADLINE=$(( $(date +%s) + ${WATCH_DEADLINE_MIN:-720} * 60 ))
NEXT_KICKER=$(( $(date +%s) + KICKER_INTERVAL ))
if [ -n "${WATCH_DEADLINE_SEC:-}" ]; then
  DEADLINE=$(( $(date +%s) + WATCH_DEADLINE_SEC ))
fi
SUPERVISOR_HANDLE=""
RELAY_HANDLE=""
RESOLVED_HANDLE=""
RESOLVE_REASON=""
SEEN_IDS="|"
SEEN_EVENT_KEYS="|"
SEEN_CANDIDATE_KEYS="|"
SEEN_MALFORMED="|"
SEEN_ROSTER_DIAGNOSTICS="|"
MISROUTED_SENT_KEYS="|"
MISROUTED_WAKE_KEYS="|"
LATE_RECOVERED_KEYS="|"
CHECK_DIAGNOSTIC=""
DELIVERY_OK=1

has_key() {
  case "$1" in *"|$2|"*) return 0 ;; *) return 1 ;; esac
}
diagnose_roster_once() {
  local key="$1:$2"
  has_key "$SEEN_ROSTER_DIAGNOSTICS" "$key" && return 0
  SEEN_ROSTER_DIAGNOSTICS="$SEEN_ROSTER_DIAGNOSTICS$key|"
  echo "ROSTER_FAIL_CLOSED role=$1 reason=$2"
}
resolve_role_current() {
  local role="$1" output status handle
  RESOLVED_HANDLE=""
  RESOLVE_REASON=""
  output=$( "$ORCA_BIN" roster resolve --project "$PROJECT" --board "$BOARD" --role "$role" --run "$PROJECT_RUN_ID" --json 2>&1 )
  status=$?
  if [ "$status" -ne 0 ]; then
    case "$output" in
      *role_roster_ambiguous*) RESOLVE_REASON=ambiguous ;;
      *role_roster_not_found*) RESOLVE_REASON=not_found ;;
      *no\ live\ terminal*) RESOLVE_REASON=no_live_terminal ;;
      *) RESOLVE_REASON=resolve_failed ;;
    esac
    return 1
  fi
  handle=$(printf '%s' "$output" | python3 -c '
import json,sys
try:
    result=(json.load(sys.stdin).get("result") or {})
except Exception:
    raise SystemExit(0)
print(result.get("currentHandle") or result.get("current_handle") or "")
')
  [ -n "$handle" ] || { RESOLVE_REASON=no_live_terminal; return 1; }
  RESOLVED_HANDLE="$handle"
}
refresh_supervisor_handle() {
  if ! resolve_role_current "$SUPERVISOR_ROLE"; then
    diagnose_roster_once "$SUPERVISOR_ROLE" "$RESOLVE_REASON"
    return 1
  fi
  SUPERVISOR_HANDLE="$RESOLVED_HANDLE"
}
refresh_relay_handle() {
  if ! resolve_role_current "$RELAY_ROLE"; then
    diagnose_roster_once "$RELAY_ROLE" "$RESOLVE_REASON"
    return 1
  fi
  RELAY_HANDLE="$RESOLVED_HANDLE"
}
send_text_then_enter() {
  local handle="$1" text="$2"
  "$ORCA_BIN" terminal send --terminal "$handle" --text "$text" --json >/dev/null 2>&1 || return 1
  "$ORCA_BIN" terminal send --terminal "$handle" --enter --json >/dev/null 2>&1 || return 1
}
emit_signal() {
  local signal_line="$1" wake_instruction="${2:-판 상태를 확인하고 중복 카드 없이 처리하세요.}"
  echo "$signal_line"
  refresh_supervisor_handle || {
    echo "WAKE_FAIL roster_resolve role=$SUPERVISOR_ROLE reason=$RESOLVE_REASON"
    return 1
  }
  CALLER_TERMINAL_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
  if [ -z "$CALLER_TERMINAL_HANDLE" ] || [ "$CALLER_TERMINAL_HANDLE" != "$SUPERVISOR_HANDLE" ]; then
    echo "CHECK_DIAGNOSTIC consumer_owner_mismatch expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing}"
    return 1
  fi
  send_text_then_enter "$SUPERVISOR_HANDLE" "[ORCA_INBOX_WAKE] $signal_line $wake_instruction" || {
    echo "WAKE_FAIL $SUPERVISOR_HANDLE"
    return 1
  }
}
log_relay_event() {
  local event="$1" timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S %z")
  echo "$event"
  [ -n "$RELAY_LOG_FILE" ] || return 0
  mkdir -p "$(dirname "$RELAY_LOG_FILE")" 2>/dev/null || return 1
  printf '%s|%s\n' "$timestamp" "$event" >> "$RELAY_LOG_FILE" || return 1
}
decode_b64() {
  local value="$1"
  printf '%s' "$value" | base64 --decode 2>/dev/null || printf '%s' "$value" | base64 -D 2>/dev/null || true
}

parse_delivery() {
  python3 -c '
import base64,json,re,sys
U="\x1c"
try:
    root=json.load(sys.stdin)
    result=root.get("result") or {}
    messages=result.get("messages") or []
    delivery_id=result.get("deliveryId") or result.get("delivery_id")
    if not delivery_id:
        if messages: raise ValueError("delivery_shape")
        print("EMPTY"); raise SystemExit(0)
    if not isinstance(messages,list): raise ValueError("delivery_shape")
    rows=[]
    for message in messages:
        if not isinstance(message,dict): raise ValueError("message_shape")
        message_id=message.get("id") or message.get("messageId") or message.get("message_id")
        sender=message.get("from") or message.get("sender") or message.get("fromHandle") or message.get("from_handle") or message.get("senderHandle") or message.get("sender_handle")
        message_type=str(message.get("type") or "")
        payload=message.get("payload") or {}
        if isinstance(payload,str): payload=json.loads(payload)
        if not isinstance(payload,dict) or not message_id or not sender or not message_type:
            raise ValueError("message_shape")
        task_id=message.get("taskId") or message.get("task_id") or payload.get("taskId") or payload.get("task_id")
        dispatch_id=message.get("dispatchId") or message.get("dispatch_id") or payload.get("dispatchId") or payload.get("dispatch_id")
        upper=payload.get("upperReport")
        if upper is None: upper=payload.get("upper_report")
        upper_report="true" if upper is True or str(upper).strip().lower()=="true" else ""
        super_reply=payload.get("superReply")
        if super_reply is None: super_reply=payload.get("super_reply")
        super_reply="true" if super_reply is True or str(super_reply).strip().lower()=="true" else ""
        target_run_id=payload.get("targetRunId") or payload.get("target_run_id") or ""
        candidate=payload.get("relayCandidate")
        if candidate is None: candidate=payload.get("relay_candidate")
        if candidate is None: candidate=payload.get("candidate")
        kind=payload.get("kind") or payload.get("candidateKind") or payload.get("candidate_kind")
        is_candidate="true" if message_type in ("relay_candidate","relay-candidate") or candidate is True or str(candidate).strip().lower()=="true" or str(kind) in ("relay_candidate","relay-candidate","human_decision_candidate") else ""
        ambiguous=payload.get("contextAmbiguous")
        if ambiguous is None: ambiguous=payload.get("context_ambiguous")
        if ambiguous is None: ambiguous=payload.get("timeAmbiguous")
        if ambiguous is None: ambiguous=payload.get("time_ambiguous")
        candidate_ambiguous="true" if ambiguous is True or str(ambiguous).strip().lower()=="true" else ""
        cursor=payload.get("outputCursor") or payload.get("output_cursor") or payload.get("supervisorOutputCursor") or payload.get("supervisor_output_cursor") or payload.get("cursor") or ""
        snippet=payload.get("boundedSnippet") or payload.get("bounded_snippet") or payload.get("snippet") or payload.get("summary") or ""
        def short(value,limit=120):
            return re.sub(r"\s+"," ",str(value or "")).replace(U," ").strip()[:limit]
        def b64(value): return base64.urlsafe_b64encode(short(value,240).encode()).decode()
        error_code=short(payload.get("errorCode") or payload.get("error_code"),80)
        effects=payload.get("effectsApplied")
        if effects is None: effects=payload.get("effects_applied")
        effects_applied="false" if effects is False or str(effects).strip().lower()=="false" else ""
        outcome=short(payload.get("outcome"),80)
        next_action=short(payload.get("nextAction") or payload.get("next_action"),80)
        body=short(message.get("subject") or message.get("body"),120)
        fields=(message_id,message_type,sender,task_id,dispatch_id,b64(body),upper_report,
                outcome,next_action,error_code,effects_applied,is_candidate,short(cursor,80),
                b64(snippet),candidate_ambiguous,super_reply,short(target_run_id,120))
        rows.append("MESSAGE"+U+U.join(str(x or "") for x in fields))
    print("DELIVERY|"+str(delivery_id))
    for row in rows: print(row)
except ValueError as error:
    print("ERROR|"+str(error))
except Exception:
    print("ERROR|delivery_shape")
'
}

project_ledger_state() {
  local task_id="$1" dispatch_id="$2" candidate_ambiguous="${3:-}" data state
  if [ "$candidate_ambiguous" = true ]; then echo ambiguous; return 0; fi
  data=$( "$ORCA_BIN" orchestration inbox --full --limit "$LEDGER_SCAN_LIMIT" --json 2>/dev/null ) || {
    echo unknown
    return 0
  }
  state=$(printf '%s' "$data" | env TASK_ID="$task_id" DISPATCH_ID="$dispatch_id" PROJECT_RUN_ID="$PROJECT_RUN_ID" python3 -c '
import json,os,sys
try:
    messages=(json.load(sys.stdin).get("result") or {}).get("messages")
    if not isinstance(messages,list): raise ValueError
except Exception:
    print("unknown"); raise SystemExit(0)
task_id=os.environ["TASK_ID"]; dispatch_id=os.environ["DISPATCH_ID"]; project_run=os.environ["PROJECT_RUN_ID"]
matches=0
for message in messages:
    if not isinstance(message,dict): continue
    run_id=str(message.get("run_id") or message.get("runId") or "")
    if run_id != project_run: continue
    message_type=str(message.get("type") or "")
    if message_type not in {"decision_gate","ask","question","escalation"}: continue
    payload=message.get("payload") or {}
    if isinstance(payload,str):
        try: payload=json.loads(payload)
        except Exception: payload={}
    if not isinstance(payload,dict): payload={}
    relay_candidate=payload.get("relayCandidate")
    if relay_candidate is None: relay_candidate=payload.get("relay_candidate")
    generated=payload.get("misroutedHumanDecision")
    if generated is None: generated=payload.get("misrouted_human_decision")
    subject=str(message.get("subject") or "")
    if str(relay_candidate).lower()=="true" or str(generated).lower()=="true" or subject.startswith("misrouted_human_decision:"):
        continue
    message_task=str(message.get("taskId") or message.get("task_id") or payload.get("taskId") or payload.get("task_id") or "")
    message_dispatch=str(message.get("dispatchId") or message.get("dispatch_id") or payload.get("dispatchId") or payload.get("dispatch_id") or "")
    if message_task==task_id and message_dispatch==dispatch_id:
        matches += 1
        if matches > 1:
            print("ambiguous"); raise SystemExit(0)
print("present" if matches==1 else "absent")
')
  case "$state" in present|absent|ambiguous|unknown) echo "$state" ;; *) echo unknown ;; esac
}

request_relay_context() {
  local message_id="$1" task_id="$2" dispatch_id="$3" output_cursor="$4" snippet="$5"
  refresh_relay_handle || {
    log_relay_event "relay_context_request_failed message=$message_id task=${task_id:-missing} dispatch=${dispatch_id:-missing} reason=roster_$RESOLVE_REASON"
    return 1
  }
  snippet=$(printf '%s' "$snippet" | python3 -c 'import re,sys; print(re.sub(r"\s+"," ",sys.stdin.read()).strip()[:240])')
  local text="[RELAY_CONTEXT_REQUIRED] candidate message=$message_id taskId=${task_id:-missing} dispatchId=${dispatch_id:-missing} outputCursor=${output_cursor:-missing} boundedSnippet=$snippet. Only this bounded snippet may be reconsidered; do not send full output or scrollback. Report a new structured relay_candidate with corrected IDs and cursor."
  send_text_then_enter "$RELAY_HANDLE" "$text" || {
    log_relay_event "relay_context_request_failed message=$message_id task=${task_id:-missing} dispatch=${dispatch_id:-missing} reason=terminal_send"
    return 1
  }
  log_relay_event "relay_context_requested message=$message_id task=${task_id:-missing} dispatch=${dispatch_id:-missing} cursor=${output_cursor:-missing} wake=1"
}

handle_relay_candidate() {
  local message_id="$1" task_id="$2" dispatch_id="$3" body="$4" output_cursor="$5" snippet="$6" candidate_ambiguous="$7"
  local candidate_key pair_key ledger_state subject project_body
  if [ -n "$task_id" ] && [ -n "$dispatch_id" ] && [ -n "$output_cursor" ]; then
    candidate_key="$task_id:$dispatch_id:$output_cursor"
  else
    candidate_key="message:$message_id"
  fi
  if has_key "$SEEN_CANDIDATE_KEYS" "$candidate_key"; then
    echo "RELAY_CANDIDATE_DUPLICATE task=${task_id:-missing} dispatch=${dispatch_id:-missing} cursor=${output_cursor:-missing} wake=0"
    return 0
  fi
  if [ -z "$task_id" ] || [ -z "$dispatch_id" ]; then
    request_relay_context "$message_id" "$task_id" "$dispatch_id" "$output_cursor" "${snippet:-$body}" || return 1
    SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
    return 0
  fi
  ledger_state=$(project_ledger_state "$task_id" "$dispatch_id" "$candidate_ambiguous")
  case "$ledger_state" in
    present)
      pair_key="$task_id:$dispatch_id"
      if has_key "$LATE_RECOVERED_KEYS" "$pair_key"; then
        echo "RELAY_CANDIDATE_DUPLICATE task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=0"
      else
        LATE_RECOVERED_KEYS="$LATE_RECOVERED_KEYS$pair_key|"
        log_relay_event "late_recovered task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=0"
      fi
      SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
      ;;
    ambiguous|unknown)
      request_relay_context "$message_id" "$task_id" "$dispatch_id" "$output_cursor" "${snippet:-$body}" || return 1
      SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
      ;;
    absent)
      pair_key="$task_id:$dispatch_id"
      subject="misrouted_human_decision:$task_id"
      project_body="relay가 bounded supervisor 출력에서 사람 판단 후보를 구조화해 보냈지만 같은 taskId+dispatchId의 공식 project Run decision_gate/ask/escalation 편지를 찾지 못했습니다. 카드 상태는 바꾸지 말고 현재 project supervisor가 후보와 장부를 확인하세요. dispatchId=$dispatch_id outputCursor=${output_cursor:-missing} boundedSnippet=${snippet:-$body}"
      if ! has_key "$MISROUTED_SENT_KEYS" "$pair_key"; then
        "$ORCA_BIN" orchestration send --run "$PROJECT_RUN_ID" --subject "$subject" --body "$project_body" --type escalation --task-id "$task_id" --dispatch-id "$dispatch_id" --payload '{"misroutedHumanDecision":true}' --json >/dev/null 2>&1 || {
          log_relay_event "misrouted_human_decision_send_failed task=$task_id dispatch=$dispatch_id reason=project_run_send wake=0"
          return 1
        }
        MISROUTED_SENT_KEYS="$MISROUTED_SENT_KEYS$pair_key|"
        echo "MISROUTED_HUMAN_DECISION_SENT subject=$subject task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing}"
      fi
      if ! has_key "$MISROUTED_WAKE_KEYS" "$pair_key"; then
        emit_signal "MISROUTED_HUMAN_DECISION task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing}" "project Run의 공식 장부에 같은 taskId+dispatchId 편지가 없어서 확인이 필요합니다. 후보 의미를 키워드로 재판정하지 마세요." || {
          log_relay_event "misrouted_human_decision_wake_failed task=$task_id dispatch=$dispatch_id reason=supervisor_send"
          return 1
        }
        MISROUTED_WAKE_KEYS="$MISROUTED_WAKE_KEYS$pair_key|"
        log_relay_event "misrouted_human_decision task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=1"
      else
        echo "MISROUTED_DUPLICATE task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} wake=0"
      fi
      SEEN_CANDIDATE_KEYS="$SEEN_CANDIDATE_KEYS$candidate_key|"
      ;;
    *)
      log_relay_event "project_ledger_check_failed task=$task_id dispatch=$dispatch_id cursor=${output_cursor:-missing} state=$ledger_state"
      return 1
      ;;
  esac
}

diagnose_check_once() {
  local kind="$1"
  [ "$CHECK_DIAGNOSTIC" = "$kind" ] && return 0
  CHECK_DIAGNOSTIC="$kind"
  echo "CHECK_DIAGNOSTIC $kind"
}

process_delivery() {
  local delivery="$1"
  local record message_id message_type sender task_id dispatch_id summary_b64 upper_report outcome next_action error_code effects_applied
  local super_reply target_run_id
  local is_candidate output_cursor snippet_b64 candidate_ambiguous summary snippet event_key malformed_key relay_now
  local is_lifecycle is_structured_upper is_super_reply is_lifecycle_error
  DELIVERY_OK=1
  while IFS=$'\034' read -r record message_id message_type sender task_id dispatch_id summary_b64 upper_report outcome next_action error_code effects_applied is_candidate output_cursor snippet_b64 candidate_ambiguous super_reply target_run_id; do
    [ "$record" = MESSAGE ] || continue
    has_key "$SEEN_IDS" "$message_id" && continue
    summary=$(decode_b64 "$summary_b64")
    if [ "$is_candidate" = true ]; then
      snippet=$(decode_b64 "$snippet_b64")
      handle_relay_candidate "$message_id" "$task_id" "$dispatch_id" "$summary" "$output_cursor" "$snippet" "$candidate_ambiguous" || {
        DELIVERY_OK=0
        break
      }
      SEEN_IDS="$SEEN_IDS$message_id|"
      continue
    fi

    is_lifecycle=0
    case "$message_type" in worker_done|escalation|decision_gate|question|ask) is_lifecycle=1 ;; esac
    is_structured_upper=0
    [ "$message_type" = status ] && [ "$upper_report" = true ] && is_structured_upper=1
    is_super_reply=0
    [ "$message_type" = status ] && [ "$super_reply" = true ] && [ -n "$target_run_id" ] && is_super_reply=1
    is_lifecycle_error=0
    if [ -n "$error_code" ] || [ "$effects_applied" = false ]; then is_lifecycle_error=1; fi
    if [ "$is_lifecycle" -eq 0 ] && [ "$is_structured_upper" -eq 0 ] && [ "$is_super_reply" -eq 0 ] && [ "$is_lifecycle_error" -eq 0 ]; then
      SEEN_IDS="$SEEN_IDS$message_id|"
      continue
    fi

    if [ "$is_super_reply" -eq 0 ] && { [ -z "$task_id" ] || [ -z "$dispatch_id" ] || { [ "$is_structured_upper" -eq 1 ] && { [ -z "$outcome" ] || [ -z "$next_action" ]; }; }; }; then
      malformed_key="malformed:$message_id"
      if ! has_key "$SEEN_MALFORMED" "$malformed_key"; then
        SEEN_MALFORMED="$SEEN_MALFORMED$malformed_key|"
        emit_signal "MALFORMED_LIFECYCLE_REPORT type=$message_type sender=$sender message=$message_id summary=$summary" "식별자가 빠진 보고는 상태에 적용하지 않았습니다. taskId+dispatchId를 갖춘 구조화 보고를 다시 보내세요." || {
          DELIVERY_OK=0
          break
        }
      fi
      DELIVERY_OK=0
      break
    fi

    if [ "$is_lifecycle_error" -eq 1 ]; then
      event_key="lifecycle_error:$task_id:$dispatch_id"
      if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$message_id|"; continue; fi
      emit_signal "LIFECYCLE_ERROR type=$message_type sender=$sender task=$task_id dispatch=$dispatch_id code=${error_code:-effectsApplied=false} summary=$summary" "같은 명령을 무작정 재시도하지 말고 pending 보고를 확인하세요." || {
        DELIVERY_OK=0
        break
      }
      SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      SEEN_IDS="$SEEN_IDS$message_id|"
      continue
    fi

    if [ "$is_structured_upper" -eq 1 ]; then
      event_key="status_upper:$task_id:$dispatch_id"
      if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$message_id|"; continue; fi
      emit_signal "SIGNAL status_upper sender=$sender task=$task_id dispatch=$dispatch_id outcome=$outcome next=$next_action summary=$summary" "상위 보고의 outcome과 nextAction을 확인하세요." || {
        DELIVERY_OK=0
        break
      }
      SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      SEEN_IDS="$SEEN_IDS$message_id|"
      continue
    fi

    if [ "$is_super_reply" -eq 1 ]; then
      event_key="super_reply:$message_id"
      if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$message_id|"; continue; fi
      emit_signal "SIGNAL super_reply sender=$sender message=$message_id targetRunId=$target_run_id summary=$summary" "슈퍼 Run의 정상 답장을 확인하세요." || {
        DELIVERY_OK=0
        break
      }
      SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
      SEEN_IDS="$SEEN_IDS$message_id|"
      continue
    fi

    event_key="$message_type:$task_id:$dispatch_id"
    if has_key "$SEEN_EVENT_KEYS" "$event_key"; then SEEN_IDS="$SEEN_IDS$message_id|"; continue; fi
    if [ "$message_type" = worker_done ]; then
      refresh_relay_handle || true
      relay_now="$RELAY_HANDLE"
      if [ -n "$relay_now" ] && [ "$sender" = "$relay_now" ]; then SEEN_IDS="$SEEN_IDS$message_id|"; continue; fi
      "$(dirname "$0")/routing-ledger-append.sh" worker_done_auto "$BOARD" "$task_id" "{\"taskId\":\"$task_id\",\"dispatchId\":\"$dispatch_id\",\"sender\":\"$sender\"}" 2>/dev/null || true
    fi
    emit_signal "SIGNAL $message_type $sender task=$task_id dispatch=$dispatch_id summary=$summary" || {
      DELIVERY_OK=0
      break
    }
    SEEN_EVENT_KEYS="$SEEN_EVENT_KEYS$event_key|"
    SEEN_IDS="$SEEN_IDS$message_id|"
  done <<< "$delivery"
}

# A1: supervisor가 소유한 pane에서만 Delivery를 소비한다.
refresh_supervisor_handle || {
  echo "ROSTER_FAIL_CLOSED role=$SUPERVISOR_ROLE reason=$RESOLVE_REASON" >&2
  exit 4
}
CALLER_TERMINAL_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
if [ -z "$CALLER_TERMINAL_HANDLE" ] || [ "$CALLER_TERMINAL_HANDLE" != "$SUPERVISOR_HANDLE" ]; then
  echo "CHECK_DIAGNOSTIC consumer_owner_mismatch expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing}"
  exit 4
fi

trap 'exit 0' INT TERM
trap '' HUP
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  NOW=$(date +%s)
  if refresh_supervisor_handle; then
    CALLER_TERMINAL_HANDLE="${ORCA_TERMINAL_HANDLE:-}"
    if [ -z "$CALLER_TERMINAL_HANDLE" ] || [ "$CALLER_TERMINAL_HANDLE" != "$SUPERVISOR_HANDLE" ]; then
      echo "CHECK_DIAGNOSTIC consumer_owner_mismatch expected=$SUPERVISOR_HANDLE actual=${CALLER_TERMINAL_HANDLE:-missing}"
      exit 4
    fi
    OUT=$( "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --json 2>&1 )
    CHECK_STATUS=$?
    if [ "$CHECK_STATUS" -ne 0 ]; then
      case "$OUT" in
        *consumer_fenced*) diagnose_check_once consumer_fenced ;;
        *terminal_target_not_run_mailbox*) diagnose_check_once terminal_target_not_run_mailbox ;;
        *run_target_mismatch*) diagnose_check_once run_target_mismatch ;;
        *) diagnose_check_once check_failed ;;
      esac
    else
      DELIVERY=$(printf '%s' "$OUT" | parse_delivery)
      DELIVERY_HEADER=$(printf '%s\n' "$DELIVERY" | awk 'NR==1 {print; exit}')
      case "$DELIVERY_HEADER" in
        ERROR\|*) diagnose_check_once "${DELIVERY_HEADER#ERROR|}" ;;
        EMPTY) ;;
        DELIVERY\|*)
          delivery_id=${DELIVERY_HEADER#DELIVERY|}
          process_delivery "$DELIVERY"
          if [ "$DELIVERY_OK" -eq 1 ]; then
            "$ORCA_BIN" orchestration check --run "$PROJECT_RUN_ID" --ack "$delivery_id" --json >/dev/null 2>&1 || diagnose_check_once ack_failed
          fi
          ;;
        *) diagnose_check_once delivery_shape ;;
      esac
    fi
  else
    diagnose_check_once supervisor_roster_unresolved
  fi

  # 여기서는 relay 주소로 bounded 순찰 알람만 보낸다. 화면 읽기는 relay agent 몫이다.
  if [ "$NOW" -ge "$NEXT_KICKER" ]; then
    if refresh_relay_handle; then
      KICKER_TEXT="[순찰 알람] project=$PROJECT board=$BOARD run=$PROJECT_RUN_ID supervisor=$SUPERVISOR_HANDLE. 자기 판 supervisor output만 bounded 범위로 확인하세요. 도구 실행 줄 또는 Context% 증가를 확인하고 연속 무진행 횟수를 기록하세요. 2회 연속이면 정체로 보고하세요. 스피너만으로 STARTED/정상 진행을 판정하지 마세요. quoted prompt, orchestration render, old scrollback, raw 문자열은 후보 근거에서 제외하세요. 사람에게 답·승인·결정을 요구하거나 waiting_for_kyle인 넓은 후보를 taskId dispatchId outputCursor boundedSnippet을 넣은 relay_candidate 편지로 project Run에 구조화하세요. ID가 없거나 시간·장부가 모호할 때만 boundedSnippet으로 새 relay_candidate를 보내세요. relay는 super upper report나 kyle 질문을 직접 만들지 않고 카드 상태도 바꾸지 않습니다. Context 50% 또는 판 경계에서는 새 relay 세션으로 교대하세요."
      send_text_then_enter "$RELAY_HANDLE" "$KICKER_TEXT" || echo "KICKER_FAIL $RELAY_HANDLE"
    else
      echo "KICKER_FAIL roster_resolve role=$RELAY_ROLE reason=$RESOLVE_REASON"
    fi
    NEXT_KICKER=$(( NOW + KICKER_INTERVAL ))
  fi
  sleep "$POLL_INTERVAL"
done
echo "DEADLINE_REACHED"
exit 1
