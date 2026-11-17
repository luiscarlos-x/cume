type StorageLike = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
const preferenceKey = 'cume-remember-login';

export function createAuthStorage(local: StorageLike | null, tab: StorageLike | null) {
  const memory = new Map<string, string>();
  const readPreference = (storage: StorageLike | null) => {
    try { return storage?.getItem(preferenceKey) ?? null; } catch { return null; }
  };
  let remember = (readPreference(tab) ?? readPreference(local)) !== 'false';
  const remove = (storage: StorageLike | null, key: string) => {
    try { storage?.removeItem(key); } catch { /* Storage can be unavailable. */ }
  };
  return {
    getRemember: () => remember,
    setRemember(value: boolean) {
      remember = value;
      for (const storage of [local, tab]) {
        try { storage?.setItem(preferenceKey, String(value)); } catch { /* Keep the in-memory preference. */ }
      }
    },
    getItem(key: string) {
      if (memory.has(key)) return memory.get(key)!;
      try { return (remember ? local : tab)?.getItem(key) ?? null; } catch { return null; }
    },
    setItem(key: string, value: string) {
      const storage = remember ? local : tab;
      remove(remember ? tab : local, key);
      try {
        if (!storage) throw new Error('Storage unavailable');
        storage.setItem(key, value);
        memory.delete(key);
      } catch { memory.set(key, value); }
    },
    removeItem(key: string) {
      memory.delete(key);
      remove(local, key);
      remove(tab, key);
    }
  };
}

export function createBrowserAuthStorage() {
  let local: StorageLike | null = null, tab: StorageLike | null = null;
  try { local = window.localStorage; } catch { /* Browsers may block storage. */ }
  try { tab = window.sessionStorage; } catch { /* Fall back to memory. */ }
  return createAuthStorage(local, tab);
}
