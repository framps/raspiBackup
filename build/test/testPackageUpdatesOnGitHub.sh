#!/bin/bash
# vim: set expandtab:
#######################################################################################################################
#
#    Run testPackageUpdates.sh on a GitHub arm64 runner
#
#######################################################################################################################
#
#    Copyright (c) 2026 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#######################################################################################################################

set -euo pipefail

usage() {
    cat <<"EOF_USAGE"
Usage:

        testPackageUpdatesOnGitHub.sh [options]

Runs testPackageUpdates.sh on a GitHub arm64 runner, waits for the result and displays the
summary report. Report and log are saved in a local directory.

A temporary commit on top of the tested commit adds the workflow packageTest.yml of this
directory as .github/workflows/packageTest.yml. It's pushed to branch test-packageTest, which
starts the workflow, and the branch is deleted afterwards. No other branch is changed.

Only committed and pushed changes are tested, as with testPackageUpdates.sh.

Options:

    -s | --source <ref>  git branch, tag or commit to test (default: HEAD)
    -l | --lintian       check the packages with lintian (slow)
    -n | --no-wait       start the test only, don't wait for the result
    -k | --keep          keep branch test-packageTest afterwards
    -h | --help          display this short help

Requires the GitHub CLI gh (authenticated with 'gh auth login').

EOF_USAGE
}

readonly TEST_BRANCH="test-packageTest"
readonly WORKFLOW="packageTest.yml"
readonly REMOTE="origin"

SOURCE_REF="HEAD"
LINTIAN=0
WAIT=1
KEEP=0

while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -s|--source) SOURCE_REF="${2:?missing git reference}"; shift 2 ;;
        -l|--lintian) LINTIAN=1; shift ;;
        -n|--no-wait) WAIT=0; shift ;;
        -k|--keep) KEEP=1; shift ;;
        *) echo "Unknown option $1"; usage; exit 1 ;;
    esac
done

command -v gh > /dev/null || { echo "GitHub CLI gh missing, see https://cli.github.com"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source_commit="$(git rev-parse --verify "${SOURCE_REF}^{commit}")" || { echo "Unknown git reference $SOURCE_REF"; exit 1; }
source_name="$(git rev-parse --abbrev-ref "$SOURCE_REF" 2>/dev/null || echo "$SOURCE_REF")"

if [[ "$SOURCE_REF" == HEAD && -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Note: uncommitted changes aren't tested"
fi
git fetch -q "$REMOTE"
if ! git branch -r --contains "$source_commit" | grep -q .; then
    echo "Note: $source_name (${source_commit:0:12}) isn't pushed yet, it's pushed with the test commit only"
fi

# temporary commit: tested commit plus the workflow
index="$(mktemp)"
trap 'rm -f "$index"' EXIT
export GIT_INDEX_FILE="$index"
git read-tree "$source_commit"
blob="$(git hash-object -w "$SCRIPT_DIR/$WORKFLOW")"
git update-index --add --cacheinfo "100644,$blob,.github/workflows/$WORKFLOW"
tree="$(git write-tree)"
unset GIT_INDEX_FILE

message="Package update test of $source_name (${source_commit:0:12})"
(( LINTIAN )) && message+=" [lintian]"
test_commit="$(git commit-tree "$tree" -p "$source_commit" -m "$message")"

echo "Starting: $message"
git push -q --force "$REMOTE" "$test_commit:refs/heads/$TEST_BRANCH"

deleteBranch() {
    (( KEEP )) || git push -q "$REMOTE" --delete "$TEST_BRANCH" 2>/dev/null || true
}

run_id=""
for (( i = 0; i < 30; i++ )); do
    run_id="$(gh run list --workflow "$WORKFLOW" --commit "$test_commit" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
    [[ -n "$run_id" ]] && break
    sleep 2
done
if [[ -z "$run_id" ]]; then
    echo "??? Workflow run for ${test_commit:0:12} not found, see the Actions tab on GitHub"
    exit 1
fi

url="$(gh run view "$run_id" --json url -q .url)"
echo "Run: $url"

if (( ! WAIT )); then
    echo "Branch $TEST_BRANCH is kept, delete it afterwards with: git push $REMOTE --delete $TEST_BRANCH"
    exit 0
fi

# the branch is needed until the runner checked out the commit, but deleting it doesn't stop the run
trap 'rm -f "$index"; deleteBranch' EXIT

rc=0
gh run watch "$run_id" --interval 30 --exit-status > /dev/null || rc=$?

results="$SCRIPT_DIR/packageTest-results/$run_id"
mkdir -p "$results"
if gh run download "$run_id" --dir "$results" > /dev/null 2>&1; then
    find "$results" -name '*.report' -exec cat {} \;
    echo "Report and log: $results"
else
    echo "No report available, see $url"
fi

if (( rc )); then
    echo "Package update test FAILED: $url"
else
    echo "Package update test PASSED"
fi
exit "$rc"
