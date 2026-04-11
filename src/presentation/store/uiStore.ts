import { create } from 'zustand';

type DetailTab = 'request' | 'response' | 'analysis' | 'aiflow';
type Locale = 'ko' | 'en';

interface UiState {
  detailTab: DetailTab;
  search: string;
  mechFilter: string | null;
  locale: Locale;
  searchNavIdx: number;
  searchNavTotal: number;
  setDetailTab: (tab: DetailTab) => void;
  setSearch: (search: string) => void;
  setMechFilter: (filter: string | null) => void;
  setLocale: (locale: Locale) => void;
  setSearchNavIdx: (n: number) => void;
  setSearchNavTotal: (n: number) => void;
}

const storedLocale = (localStorage.getItem('claude-inspector-locale') ?? 'ko') as Locale;

export const useUiStore = create<UiState>((set) => ({
  detailTab: 'aiflow',
  search: '',
  mechFilter: null,
  locale: storedLocale,
  searchNavIdx: 0,
  searchNavTotal: 0,

  setDetailTab: (detailTab) => set({ detailTab }),
  setSearch: (search) => set({ search, searchNavIdx: 0, searchNavTotal: 0 }),
  setMechFilter: (mechFilter) => set({ mechFilter }),
  setSearchNavIdx: (searchNavIdx) => set({ searchNavIdx }),
  setSearchNavTotal: (searchNavTotal) => set({ searchNavTotal }),
  setLocale: (locale) => {
    localStorage.setItem('claude-inspector-locale', locale);
    set({ locale });
  },
}));
