import { create } from 'zustand';

type DetailTab = 'request' | 'response' | 'analysis' | 'aiflow';
type Locale = 'ko' | 'en';

interface UiState {
  detailTab: DetailTab;
  search: string;
  mechFilter: string | null;
  locale: Locale;
  setDetailTab: (tab: DetailTab) => void;
  setSearch: (search: string) => void;
  setMechFilter: (filter: string | null) => void;
  setLocale: (locale: Locale) => void;
}

const storedLocale = (localStorage.getItem('claude-inspector-locale') ?? 'ko') as Locale;

export const useUiStore = create<UiState>((set) => ({
  detailTab: 'aiflow',
  search: '',
  mechFilter: null,
  locale: storedLocale,

  setDetailTab: (detailTab) => set({ detailTab }),
  setSearch: (search) => set({ search }),
  setMechFilter: (mechFilter) => set({ mechFilter }),
  setLocale: (locale) => {
    localStorage.setItem('claude-inspector-locale', locale);
    set({ locale });
  },
}));
