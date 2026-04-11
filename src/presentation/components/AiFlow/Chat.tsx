import { useCallback, useRef, useState } from 'react';
import { useDI } from '../../di/container';
import { useAiflowStore } from '../../store/aiflowStore';
import { useUiStore } from '../../store/uiStore';
import { t } from '../../../i18n';
import type { ChatMessage } from '../../../application/usecases/SendChatMessageUseCase';

export function Chat() {
  const { sendChat } = useDI();
  const chatMessages = useAiflowStore((s) => s.chatMessages);
  const chatting = useAiflowStore((s) => s.chatting);
  const chatPartial = useAiflowStore((s) => s.chatPartial);
  const addChatMessage = useAiflowStore((s) => s.addChatMessage);
  const setChatting = useAiflowStore((s) => s.setChatting);
  const appendChatChunk = useAiflowStore((s) => s.appendChatChunk);
  const finalizeChatMessage = useAiflowStore((s) => s.finalizeChatMessage);
  const locale = useUiStore((s) => s.locale);

  const [input, setInput] = useState('');
  const messagesRef = useRef<HTMLDivElement>(null);

  const send = useCallback(async () => {
    const text = input.trim();
    if (!text || chatting) return;
    setInput('');
    const userMsg: ChatMessage = { role: 'user', content: text };
    addChatMessage(userMsg);
    setChatting(true);

    try {
      const allMessages = [...chatMessages, userMsg];
      await sendChat.execute(
        allMessages,
        null, // aiflowResult not passed here; usecase builds its own context
        (chunk) => appendChatChunk(chunk),
      );
      finalizeChatMessage();
    } catch {
      finalizeChatMessage();
    }

    setTimeout(() => {
      messagesRef.current?.scrollTo({ top: messagesRef.current.scrollHeight, behavior: 'smooth' });
    }, 50);
  }, [addChatMessage, appendChatChunk, chatMessages, chatting, finalizeChatMessage, input, sendChat, setChatting]);

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  };

  return (
    <div className="aiflow-chat">
      <div className="aiflow-chat-header">{t(locale, 'aiflow.chatHeader')}</div>
      <div className="aiflow-chat-messages" ref={messagesRef}>
        {chatMessages.map((msg, i) => (
          <div key={i} className={`chat-bubble ${msg.role}`}>
            {msg.content}
          </div>
        ))}
        {chatting && chatPartial && (
          <div className="chat-bubble assistant streaming">{chatPartial}</div>
        )}
        {chatting && !chatPartial && (
          <div className="chat-bubble assistant">
            <div className="chat-typing">
              <span /><span /><span />
            </div>
          </div>
        )}
      </div>
      <div className="aiflow-chat-input">
        <textarea
          className="aiflow-chat-textarea"
          placeholder={t(locale, 'aiflow.chatPlaceholder')}
          value={input}
          rows={2}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          disabled={chatting}
        />
        <button
          className="aiflow-chat-send"
          onClick={send}
          disabled={chatting || !input.trim()}
        >
          {t(locale, 'aiflow.chatSend')}
        </button>
      </div>
    </div>
  );
}
