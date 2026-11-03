
# A stub kit-init wrote: kit-init does not know this stack's test runner. Put
# the job's checks here, its counts line last, and refuse when a tool is
# absent or off its pin, as the other arms do.
arm_@@FN@@() {
  refuse "The @@JOB@@ arm is a stub kit-init wrote; put its checks in @@ADAPTER@@, so ${job} did not run."
}
