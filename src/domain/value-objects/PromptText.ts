/** PromptText — 분석 프롬프트 값 객체 (불변, 빈 텍스트 불허) */
export class PromptText {
  private constructor(readonly value: string) {}

  static create(text: string): PromptText {
    if (!text || text.trim().length === 0) {
      throw new Error('PromptText cannot be empty');
    }
    return new PromptText(text);
  }
}
