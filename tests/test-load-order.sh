#!/bin/zsh
# ABOUTME: Regression test for the telos load-order bug — compiles and loads
# cl-llm-provider in FRESH images across every combination of "was the real telos
# loaded first", with an emptied fasl cache between cells.
#
# This bug is structurally invisible to FiveAM: any in-image test runs in a
# process that has already loaded the system, which is exactly the state that
# hides it. It needs separate processes and a cold cache, so it lives here.
#
# The cache is ALWAYS a private throwaway dir. This test must never write to
# ~/.cache/common-lisp — poisoning that cache is the failure mode under test.
#
# usage: tests/test-load-order.sh        (exit 0 = all orders load cleanly)

set -u

CACHE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cllp-load-order.XXXXXX")
trap 'rm -rf "$CACHE_ROOT"' EXIT
# Resolve symlinks: on macOS mktemp hands back /var/..., ASDF reports the
# physical /private/var/..., and the containment check below would reject its
# own cache dir.
CACHE_ROOT=$(cd "$CACHE_ROOT" && pwd -P)
export XDG_CACHE_HOME=$CACHE_ROOT

# Fail loudly rather than silently testing nothing if the shared cache is in play.
if [[ "$CACHE_ROOT" == "$HOME/.cache"* ]]; then
  print -u2 "REFUSING: cache root resolved inside the shared cache"
  exit 2
fi

# Ask ASDF where it will actually write, rather than globbing a guessed layout.
# A glob that stops matching would make wipe_cache a silent no-op, and every
# cell after the first would reuse the previous cell's fasls and report PASS
# without a single cold compile — a green test that tests nothing.
FASL_DIRS=$(sbcl --noinform --non-interactive --eval '
  (handler-case
      (dolist (system (list "cl-llm-provider" "telos"))
        (format t "~&FASLDIR ~a~%"
                (namestring (asdf:apply-output-translations
                             (asdf:system-source-directory system)))))
    (error (e) (format t "~&FASLDIR-ERROR ~a~%" e)))' 2>/dev/null \
  | grep "^FASLDIR " | cut -d' ' -f2-)

# Assert BOTH dirs resolved, not merely one. A half-resolved list would let
# wipe_cache leave telos's fasls warm, so the "compiled in a telos-first image"
# arm would stop being a cold compile — green while testing less than it claims.
if [[ $(print -r -- "$FASL_DIRS" | grep -c .) -ne 2 ]]; then
  print -u2 "REFUSING: expected 2 ASDF output dirs (cl-llm-provider, telos), got:"
  print -u2 "${FASL_DIRS:-<none>}"
  exit 2
fi
while IFS= read -r d; do
  if [[ "$d" != "$CACHE_ROOT"* ]]; then
    print -u2 "REFUSING: ASDF would write to '$d', outside the throwaway cache"
    exit 2
  fi
done <<< "$FASL_DIRS"

run_image () {          # run_image <telos-first|no-telos> ; echoes RESULT line
  local regime=$1 preload
  if [[ "$regime" == "telos-first" ]]; then
    preload='(ql:quickload :telos :silent t)'
  else
    preload='(values)'
  fi
  sbcl --noinform --disable-debugger --non-interactive \
    --eval "$preload" \
    --eval '(handler-case (progn (ql:quickload :cl-llm-provider :silent t)
                                 (format t "~&RESULT: OK~%"))
              (error (e) (format t "~&RESULT: FAIL ~a: ~a~%" (type-of e) e)))' \
    2>&1 | grep -E "^RESULT:" | head -1
}

wipe_cache () {                 # cold-compile cl-llm-provider and telos; keep deps warm
  local d
  while IFS= read -r d; do rm -rf "$d"; done <<< "$FASL_DIRS"
}

failures=0
for compile_regime in no-telos telos-first; do
  for load_regime in no-telos telos-first; do
    wipe_cache
    build=$(run_image "$compile_regime")            # cold: compiles the fasls
    load=$(run_image "$load_regime")                # warm: loads those fasls
    label="compiled=${compile_regime}  loaded=${load_regime}"
    if [[ "$build" == "RESULT: OK" && "$load" == "RESULT: OK" ]]; then
      print "PASS  $label"
    else
      failures=$((failures + 1))
      print "FAIL  $label"
      [[ "$build" != "RESULT: OK" ]] && print "        build: ${build:-<no result>}"
      [[ "$load"  != "RESULT: OK" ]] && print "        load:  ${load:-<no result>}"
    fi
  done
done

# The optional bridge is the only component that touches telos, so it is the one
# component the four cells above never load. Assert FIDELITY, not just that it
# loads: publishing features while silently losing their members and decisions
# is a regression whose queries succeed and return nothing.
wipe_cache
# NOTE: the quickload and the assertions MUST be separate --eval forms. SBCL
# reads each form just before evaluating it, and the assertions name telos:
# symbols that do not exist until the bridge has been loaded — one combined form
# dies in the reader, before any handler-case can report it.
bridge=$(sbcl --noinform --disable-debugger --non-interactive \
  --eval '(handler-case (ql:quickload :cl-llm-provider/telos :silent t)
            (error (e) (format t "~&RESULT: FAIL ~a: ~a~%" (type-of e) e)
                       (uiop:quit 1)))' \
  --eval '
  (handler-case
      (progn
        (let ((features (telos:list-features))
              (members  (telos::feature-members (quote cl-llm-provider:tool-calling)))
              ;; http-transport owns 11 define-condition/i forms; membership is
              ;; published per-kind, so assert a second kind independently.
              (cond-members (telos::feature-members
                             (quote cl-llm-provider::http-transport)))
              (decisions (telos::feature-decisions
                          (quote cl-llm-provider::completion-api)))
              (class-intent (gethash (quote cl-llm-provider:llm-provider)
                                     telos::*class-intent-registry*)))
          (format t "~&RESULT: ~a~%"
                  (cond ((null (member (quote cl-llm-provider:llm-provider) features))
                         "FAIL features not published")
                        ((null (getf members :functions)) "FAIL feature members empty (functions)")
                        ((null (getf cond-members :conditions)) "FAIL feature members empty (conditions)")
                        ((zerop (length decisions))       "FAIL decisions not published")
                        ((null class-intent)              "FAIL classes not filed as classes")
                        (t "OK")))))
    (error (e) (format t "~&RESULT: FAIL ~a: ~a~%" (type-of e) e)))' 2>&1 \
  | grep -E "^RESULT:" | head -1)

if [[ "$bridge" == "RESULT: OK" ]]; then
  print "PASS  cl-llm-provider/telos bridge publishes with fidelity"
else
  failures=$((failures + 1))
  print "FAIL  cl-llm-provider/telos bridge"
  print "        ${bridge:-<no result>}"
fi

print ""
if [[ $failures -eq 0 ]]; then
  print "All 4 load orders clean, bridge faithful."
  exit 0
fi
print "$failures of 5 checks failed."
exit 1
