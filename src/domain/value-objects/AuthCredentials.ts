/** AuthCredentials — API 인증 헤더 값 객체 (불변) */
export class AuthCredentials {
  private constructor(private readonly headers: Record<string, string>) {}

  static fromHeaders(h: Record<string, string>): AuthCredentials | null {
    const auth: Record<string, string> = {};
    if (h['x-api-key']) auth['x-api-key'] = h['x-api-key'];
    if (h['authorization']) auth['authorization'] = h['authorization'];
    return Object.keys(auth).length > 0 ? new AuthCredentials(auth) : null;
  }

  get httpHeaders(): Record<string, string> {
    return { ...this.headers };
  }
}
