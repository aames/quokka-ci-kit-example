  [ -n "${@@PROJECT_UPPER@@_TEST_PG_URL:-}" ] || refuse "@@PROJECT_UPPER@@_TEST_PG_URL is not set, so ${job} did not run."
