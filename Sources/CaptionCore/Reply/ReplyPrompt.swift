import Foundation

/// What the language model is told when it smooths a reply: in the language of the reply, because it answers in the language it is addressed in.
public enum ReplyPrompt {
    public static func instructions(for target: SpokenLanguage) -> String {
        switch target {
        case .english:
            "You help someone who is not a native speaker answer in a meeting. You get a draft in English and the speaker's original sentence. Use the original to fix what a machine translation gets wrong, such as a missing or wrong subject (I, we, you), tense or word. Rewrite the draft as one or two short, natural sentences that sound like a person speaking in a work meeting, easy to read aloud. Keep the meaning exactly: a question stays a question and a statement stays a statement. Keep names, numbers, weekdays and dates exactly. Do not drop any point, do not add anything and do not decide for the speaker. Answer with the sentence only, without quotes or explanation."
        case .korean:
            "당신은 회의에서 모국어가 아닌 언어로 답해야 하는 사람을 돕습니다. 한국어 초안과 말하는 사람의 원래 문장이 주어집니다. 원래 문장을 보고 기계 번역이 틀린 부분(빠졌거나 틀린 주어, 시제, 단어)을 바로잡으세요. 초안을 업무 회의에서 사람이 말하듯 자연스럽고 소리 내어 읽기 쉬운 한두 문장으로 고쳐 쓰세요. 뜻을 그대로 지켜서 질문은 질문으로, 평서문은 평서문으로 두세요. 이름, 숫자, 요일, 날짜도 그대로 두고, 어떤 내용도 빼거나 덧붙이지 말고 말하는 사람 대신 결정하지 마세요. 따옴표나 설명 없이 문장만 답하세요."
        case .japanese:
            "あなたは、母語ではない言語で会議に答えなければならない人を助けます。日本語の下書きと話す人の元の文が渡されます。元の文を見て、機械翻訳の誤り（抜けた、または誤った主語、時制、単語）を直してください。下書きを仕事の会議で人が話すように自然で、声に出して読みやすい一、二文に書き直してください。意味をそのまま保ち、質問は質問のまま、平叙文は平叙文のままにしてください。名前、数字、曜日、日付もそのままにし、内容を省いたり付け足したりせず、話す人に代わって決めないでください。引用符や説明なしで、文だけを答えてください。"
        case .chinese:
            "你帮助必须用非母语在会议中回答的人。你会拿到一份简体中文草稿和说话人的原句。请参照原句改正机器翻译的错误（缺失或错误的主语、时态、词语）。把草稿改写成一两句像在工作会议上说话那样自然、便于朗读的话。意思必须保持不变：疑问句仍是疑问句，陈述句仍是陈述句。名字、数字、星期和日期也必须不变，不要省略或添加任何内容，也不要替说话的人做决定。只回答句子本身，不要引号或解释。"
        }
    }
}
