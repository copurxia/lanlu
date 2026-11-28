import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  getSelectFilterItems,
  toSelectFilterValue,
  toSourceFilterValue,
} from '@/lib/source-filter-options';
import type { SourceFilter } from '@/lib/services/source-plugin-service';

interface SourceSelectFilterProps {
  filter: SourceFilter;
  value: unknown;
  onValueChange: (value: string) => void;
}

export function SourceSelectFilter({
  filter,
  value,
  onValueChange,
}: SourceSelectFilterProps) {
  const selectedValue = toSelectFilterValue(value);
  const selectItems = getSelectFilterItems(filter);

  return (
    <Select
      value={selectedValue}
      onValueChange={(selectValue) => onValueChange(toSourceFilterValue(selectValue))}
    >
      <SelectTrigger className="w-auto min-w-[120px]">
        <SelectValue placeholder={filter.label} />
      </SelectTrigger>
      <SelectContent>
        {selectItems.map((option) => (
          <SelectItem key={option.value} value={option.value}>
            {option.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
