import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

import { SourceSelectFilter } from './SourceSelectFilter';
import type { SourceFilter } from '@/lib/services/source-plugin-service';

const filter: SourceFilter = {
  key: 'category',
  label: '分类',
  type: 'select',
  options: [
    { label: '同人志: 选择', value: '' },
    { label: '同人志', value: 'doujinshi' },
  ],
};

describe('SourceSelectFilter', () => {
  beforeAll(() => {
    Element.prototype.hasPointerCapture = () => false;
    Element.prototype.releasePointerCapture = () => {};
    Element.prototype.setPointerCapture = () => {};
    Element.prototype.scrollIntoView = () => {};
  });

  afterAll(() => {
    Reflect.deleteProperty(Element.prototype, 'hasPointerCapture');
    Reflect.deleteProperty(Element.prototype, 'releasePointerCapture');
    Reflect.deleteProperty(Element.prototype, 'setPointerCapture');
    Reflect.deleteProperty(Element.prototype, 'scrollIntoView');
  });

  it('shows the plugin empty-option label while collapsed and maps selection back to an empty value', async () => {
    const onValueChange = vi.fn();
    const view = render(
      <SourceSelectFilter filter={filter} value="" onValueChange={onValueChange} />
    );

    const trigger = screen.getByRole('combobox');
    expect(trigger).toHaveTextContent('同人志: 选择');

    view.rerender(
      <SourceSelectFilter
        filter={filter}
        value="doujinshi"
        onValueChange={onValueChange}
      />
    );
    expect(trigger).toHaveTextContent('同人志');

    fireEvent.pointerDown(trigger, {
      button: 0,
      ctrlKey: false,
      pointerType: 'mouse',
    });
    const emptyOption = await screen.findByRole('option', { name: '同人志: 选择' });
    fireEvent.click(emptyOption);

    expect(onValueChange).toHaveBeenCalledWith('');
  });
});
