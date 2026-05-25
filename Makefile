# Pin Maven to Temurin 21 (Checker Framework supports JDK 8/11/17/21).
# Without this, brew's `maven` picks up JDK 26 from the openjdk formula
# transitively, which Checker Framework doesn't officially support.
JAVA_HOME := /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
export JAVA_HOME

MVN := mvn -B

# Pattern matching a Checker Framework finding line in the build log.
# CF warnings have a stable shape:
#   [WARNING] /abs/path/File.java:[LINE,COL] [category] message
# where [category] may be a single word ([return], [argument]) or
# dotted ([dereference.of.nullable], [required.method.not.called]).
# We anchor on the :[LINE,COL] locator so we don't catch plain javac warnings.
CF_FINDING := ^\[WARNING\] .*\.java:\[[0-9]+,[0-9]+\] \[

.PHONY: help examples examples-clean case-study case-study-clean

help:
	@echo "Targets:"
	@echo "  examples           Compile tiny demos through all 4 checkers."
	@echo "                     Fails if any checker reports a finding."
	@echo "  examples-clean     Remove examples/target."
	@echo "  case-study         Run all 4 checkers against vendored NanoHTTPD."
	@echo "                     Fails if any checker reports a finding."
	@echo "  case-study-clean   Remove case-study/target."

examples:
	@mkdir -p examples/target
	@set -o pipefail; \
	  ( cd examples && $(MVN) compile ) 2>&1 | tee examples/target/checker.log
	@findings=$$(grep -E '$(CF_FINDING)' examples/target/checker.log | wc -l | tr -d ' '); \
	  if [ "$$findings" -gt 0 ]; then \
	    echo ""; \
	    echo "Checker Framework reported $$findings finding(s) above."; \
	    echo "(Build returned success because -Awarns demotes errors to warnings"; \
	    echo " so all four checkers can complete; this make target fails on any finding.)"; \
	    exit 1; \
	  else \
	    echo "Checker Framework found no issues."; \
	  fi

examples-clean:
	cd examples && $(MVN) clean

case-study:
	@mkdir -p case-study/target
	@set -o pipefail; \
	  ( cd case-study && $(MVN) compile ) 2>&1 | tee case-study/target/checker.log
	@findings=$$(grep -E '$(CF_FINDING)' case-study/target/checker.log | wc -l | tr -d ' '); \
	  if [ "$$findings" -gt 0 ]; then \
	    echo ""; \
	    echo "Checker Framework reported $$findings finding(s) above."; \
	    echo "Findings broken down by checker category:"; \
	    grep -oE '\[[a-z]+(\.[a-z]+)*\][^A-Z]' case-study/target/checker.log \
	      | sort | uniq -c | sort -rn | head -20; \
	    exit 1; \
	  else \
	    echo "Checker Framework found no issues."; \
	  fi

case-study-clean:
	cd case-study && $(MVN) clean
