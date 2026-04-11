import { create } from 'zustand';
import type { ProxyCapture } from '../../domain/entities/ProxyCapture';

interface CaptureState {
  captures: ProxyCapture[];
  selectedId: number | null;
  proxyRunning: boolean;
  proxyPort: number | undefined;
  addCapture: (capture: ProxyCapture) => void;
  setCaptures: (captures: ProxyCapture[]) => void;
  selectCapture: (id: number | null) => void;
  setProxyRunning: (running: boolean, port?: number) => void;
  clear: () => void;
}

export const useCaptureStore = create<CaptureState>((set) => ({
  captures: [],
  selectedId: null,
  proxyRunning: false,
  proxyPort: undefined,

  addCapture: (capture) =>
    set((s) => ({ captures: [...s.captures, capture] })),

  setCaptures: (captures) => set({ captures }),

  selectCapture: (id) => set({ selectedId: id }),

  setProxyRunning: (running, port) =>
    set({ proxyRunning: running, proxyPort: port }),

  clear: () => set({ captures: [], selectedId: null }),
}));
