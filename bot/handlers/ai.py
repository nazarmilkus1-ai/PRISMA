free_router = Router(name="ai_free")

async def _ask_ai(message: types.Message, question: str, private: bool) -> bool:
    """Ask AI a question and return whether it was successful."""
    from services.ai import ambient
    answer = await ambient.decide(-1001, "Test", question)
    return answer.get("action") == "answer"
