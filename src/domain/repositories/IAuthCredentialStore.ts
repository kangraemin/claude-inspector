import type { AuthCredentials } from '../value-objects/AuthCredentials';

export interface IAuthCredentialStore {
  get(): AuthCredentials | null;
  save(credentials: AuthCredentials): void;
}
