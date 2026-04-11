import type { IAuthCredentialStore } from '../../domain/repositories/IAuthCredentialStore';
import { AuthCredentials } from '../../domain/value-objects/AuthCredentials';

const STORAGE_KEY = 'claude-inspector-auth';

export class LocalStorageAuthStore implements IAuthCredentialStore {
  get(): AuthCredentials | null {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const headers = JSON.parse(raw) as Record<string, string>;
      return AuthCredentials.fromHeaders(headers);
    } catch {
      return null;
    }
  }

  save(credentials: AuthCredentials): void {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(credentials.httpHeaders));
  }
}
