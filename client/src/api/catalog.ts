import type {Category} from '../types/api';
import {fetchCategories, fetchSmartFilters, type SmartFilter} from './lanlu';

let categoriesInFlight: Promise<Category[]> | null = null;
let smartFiltersInFlight: Promise<SmartFilter[]> | null = null;

/**
 * Startup mounts several consumers (Home rows, Home chips, sidebar) at once.
 * Share the in-flight request instead of firing one per consumer.
 */
export function fetchCategoriesShared(): Promise<Category[]> {
  if (!categoriesInFlight) {
    categoriesInFlight = fetchCategories().finally(() => {
      categoriesInFlight = null;
    });
  }
  return categoriesInFlight;
}

export function fetchSmartFiltersShared(): Promise<SmartFilter[]> {
  if (!smartFiltersInFlight) {
    smartFiltersInFlight = fetchSmartFilters().finally(() => {
      smartFiltersInFlight = null;
    });
  }
  return smartFiltersInFlight;
}
