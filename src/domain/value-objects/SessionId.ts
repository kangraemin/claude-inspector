/**
 * SessionId — 세션 해시 값 객체 (불변)
 * 기존 main.js proxy handler의 sessionId 해시 로직과 동일
 */
export class SessionId {
  private constructor(private readonly value: string) {}

  /** 텍스트로부터 결정론적 해시 생성 (main.js 로직과 동일) */
  static fromText(text: string): SessionId {
    let hash = 0;
    for (let i = 0; i < text.length; i++) {
      hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0;
    }
    return new SessionId('session-' + Math.abs(hash).toString(36));
  }

  static fromRaw(raw: string): SessionId {
    return new SessionId(raw);
  }

  toString(): string {
    return this.value;
  }

  equals(other: SessionId): boolean {
    return this.value === other.value;
  }
}
