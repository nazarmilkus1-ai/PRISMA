import os

# The agent ships as an assistant without code access (AGENT_CODE_ACCESS off). Most agent tests exercise the code-writing
# machinery, so they run with access on; tests/test_agent_assistant.py switches it off per test.
os.environ.setdefault("AGENT_CODE_ACCESS", "1")
