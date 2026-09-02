import { parseTableParams, stringifyTableParams } from '@refinedev/core';
import type { GoConfig, RouterProvider } from '@refinedev/core';
import { Link, useLocation, useNavigate } from 'react-router-dom';

type TableQuery = Parameters<typeof stringifyTableParams>[0];

function isTableQueryKey(key: string): boolean {
  return (
    key === 'currentPage' ||
    key === 'pageSize' ||
    key === 'sorter' ||
    key.startsWith('sorters[') ||
    key === 'filters' ||
    key.startsWith('filters[')
  );
}

function searchFor(
  query: Record<string, unknown> | undefined,
  currentSearch: string,
  keepQuery: boolean,
): string {
  const params = new URLSearchParams(keepQuery ? currentSearch : '');
  if (query) {
    for (const key of [...params.keys()]) {
      if (isTableQueryKey(key)) params.delete(key);
    }
    const serialized = stringifyTableParams(query as TableQuery);
    for (const [key, value] of new URLSearchParams(serialized)) params.append(key, value);
  }
  const search = params.toString();
  return search ? `?${search}` : '';
}

export const adminRouterProvider: RouterProvider = {
  go: () => {
    const navigate = useNavigate();
    const location = useLocation();

    return (config: GoConfig) => {
      const pathname = config.to ?? location.pathname;
      const search = searchFor(config.query, location.search, config.options?.keepQuery === true);
      const hash = config.hash ?? (config.options?.keepHash ? location.hash : '');
      const target = `${pathname}${search}${hash}`;

      if (config.type === 'path') return target;
      navigate(target, { replace: config.type === 'replace' });
      return target;
    };
  },
  back: () => {
    const navigate = useNavigate();
    return () => navigate(-1);
  },
  parse: () => {
    const location = useLocation();
    return () => {
      const parsed = parseTableParams(location.search || '?');
      return {
        pathname: location.pathname,
        params: {
          currentPage:
            typeof parsed.parsedCurrentPage === 'number' ? parsed.parsedCurrentPage : undefined,
          pageSize: typeof parsed.parsedPageSize === 'number' ? parsed.parsedPageSize : undefined,
          sorters: parsed.parsedSorter,
          filters: parsed.parsedFilters,
        },
      };
    };
  },
  Link,
};
