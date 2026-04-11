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
}));
