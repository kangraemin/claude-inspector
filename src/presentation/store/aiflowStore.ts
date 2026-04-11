import { create } from 'zustand';
import type { AiFlowResult } from '../../domain/entities/AiFlowResult';
import type { ChatMessage } from '../../application/usecases/SendChatMessageUseCase';

type AiFlowState = 'idle' | 'analyzing' | 'done' | 'error';

interface AiFlowStoreState {
  aiflowState: AiFlowState;
  aiflowPartial: string | null;
  aiflowResult: AiFlowResult | null;

  optimizing: boolean;
  optPartial: string | null;
  optimization: string | null;

  chatMessages: ChatMessage[];
  chatting: boolean;
  chatPartial: string | null;

  selectedCaptureIds: Set<number>;

  setAiflowState: (state: AiFlowState) => void;
  setAiflowPartial: (partial: string | null) => void;
  setAiflowResult: (result: AiFlowResult | null) => void;

  setOptimizing: (optimizing: boolean) => void;
  setOptPartial: (partial: string | null) => void;
  setOptimization: (text: string | null) => void;

  addChatMessage: (msg: ChatMessage) => void;
  setChatting: (chatting: boolean) => void;
  setChatPartial: (partial: string | null) => void;
  appendChatChunk: (chunk: string) => void;
  finalizeChatMessage: () => void;

  toggleCaptureSelection: (id: number) => void;
  selectAllCaptures: (ids: number[]) => void;
  deselectAllCaptures: () => void;
  addCaptureToSelection: (id: number) => void;
}

export const useAiflowStore = create<AiFlowStoreState>((set) => ({
  aiflowState: 'idle',
  aiflowPartial: null,
  aiflowResult: null,

  optimizing: false,
  optPartial: null,
  optimization: null,

  chatMessages: [],
  chatting: false,
  chatPartial: null,

  selectedCaptureIds: new Set<number>(),

  setAiflowState: (aiflowState) => set({ aiflowState }),
  setAiflowPartial: (aiflowPartial) => set({ aiflowPartial }),
  setAiflowResult: (aiflowResult) => set({ aiflowResult }),

  setOptimizing: (optimizing) => set({ optimizing }),
  setOptPartial: (optPartial) => set({ optPartial }),
  setOptimization: (optimization) => set({ optimization }),

  addChatMessage: (msg) =>
    set((s) => ({ chatMessages: [...s.chatMessages, msg] })),

  setChatting: (chatting) => set({ chatting }),
  setChatPartial: (chatPartial) => set({ chatPartial }),

  appendChatChunk: (chunk) =>
    set((s) => ({ chatPartial: (s.chatPartial ?? '') + chunk })),

  finalizeChatMessage: () =>
    set((s) => {
      if (!s.chatPartial) return { chatting: false, chatPartial: null };
      const aiMsg: ChatMessage = { role: 'assistant', content: s.chatPartial };
      return {
        chatMessages: [...s.chatMessages, aiMsg],
        chatting: false,
        chatPartial: null,
      };
    }),

  toggleCaptureSelection: (id) =>
    set((s) => {
      const next = new Set(s.selectedCaptureIds);
      if (next.has(id)) next.delete(id); else next.add(id);
      return { selectedCaptureIds: next };
    }),

  selectAllCaptures: (ids) =>
    set({ selectedCaptureIds: new Set(ids) }),

  deselectAllCaptures: () =>
    set({ selectedCaptureIds: new Set<number>() }),

  addCaptureToSelection: (id) =>
    set((s) => {
      const next = new Set(s.selectedCaptureIds);
      next.add(id);
      return { selectedCaptureIds: next };
    }),
}));
