import { createContext, useContext } from 'react';
import { ElectronAnalysisService } from '../../infrastructure/electron/ElectronAnalysisService';
import { ElectronProxyGateway } from '../../infrastructure/electron/ElectronProxyGateway';
import { ElectronEventBus } from '../../infrastructure/electron/ElectronEventBus';
import { InMemoryCaptureRepository } from '../../infrastructure/repositories/InMemoryCaptureRepository';
import { LocalStorageAuthStore } from '../../infrastructure/repositories/LocalStorageAuthStore';
import { PromptBuilderService } from '../../domain/services/PromptBuilderService';
import { ResponseParserService } from '../../domain/services/ResponseParserService';
import { AnalyzeAiFlowUseCase } from '../../application/usecases/AnalyzeAiFlowUseCase';
import { OptimizeSessionUseCase } from '../../application/usecases/OptimizeSessionUseCase';
import { CancelAnalysisUseCase } from '../../application/usecases/CancelAnalysisUseCase';
import { SendChatMessageUseCase } from '../../application/usecases/SendChatMessageUseCase';
import { ManageProxyUseCase } from '../../application/usecases/ManageProxyUseCase';

export interface DIContainer {
  captureRepository: InMemoryCaptureRepository;
  eventBus: ElectronEventBus;
  analyzeAiFlow: AnalyzeAiFlowUseCase;
  optimizeSession: OptimizeSessionUseCase;
  cancelAnalysis: CancelAnalysisUseCase;
  sendChat: SendChatMessageUseCase;
  manageProxy: ManageProxyUseCase;
}

export function createContainer(): DIContainer {
  const captureRepository = new InMemoryCaptureRepository();
  const authStore = new LocalStorageAuthStore();
  const analysisService = new ElectronAnalysisService();
  const proxyGateway = new ElectronProxyGateway();
  const eventBus = new ElectronEventBus();
  const promptBuilder = new PromptBuilderService();
  const responseParser = new ResponseParserService();

  const analyzeAiFlow = new AnalyzeAiFlowUseCase(
    analysisService, captureRepository, promptBuilder, responseParser,
  );
  const optimizeSession = new OptimizeSessionUseCase(
    analysisService, captureRepository, promptBuilder,
  );
  const cancelAnalysis = new CancelAnalysisUseCase(analysisService);
  const sendChat = new SendChatMessageUseCase(
    analysisService, captureRepository,
  );
  const manageProxy = new ManageProxyUseCase(proxyGateway, captureRepository);

  void authStore; // reserved for future credential injection

  return { captureRepository, eventBus, analyzeAiFlow, optimizeSession, cancelAnalysis, sendChat, manageProxy };
}

const DIContext = createContext<DIContainer>(null!);

export const DIProvider = DIContext.Provider;
export const useDI = (): DIContainer => useContext(DIContext);
