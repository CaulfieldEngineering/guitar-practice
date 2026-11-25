import Foundation

// The model checks (ios/PracticeTests/ModelChecks.swift) on Windows: scripts/model-check.sh builds the app's
// Foundation-only files with these and runs them. Exit 1 on any failure.
var failed = 0
var total = 0
for (name, run) in ModelChecks.all {
    var c = ModelChecks()
    run(&c)
    total += c.count
    if c.failures.isEmpty {
        print("ok    \(name) (\(c.count) checks)")
    } else {
        failed += c.failures.count
        print("FAIL  \(name)")
        for f in c.failures.prefix(20) { print("      \(f)") }
    }
}
print("\(total) checks, \(failed) failed")
exit(failed == 0 ? 0 : 1)
