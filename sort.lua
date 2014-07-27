local qsort = (function()
  local function swap(data, a, b)
    data[a], data[b] = data[b], data[a]
  end

  local function median_of_three(data, begin, end_, context, is_less)
    local length = end_ - begin
    assert(length ~= 0)
    local mid = begin + length/2
    local last = end_ - 1

    if not is_less(data[begin], data[mid], context) then
      swap(data, begin, mid)
    end

    if not is_less(data[mid], data[last], context) then
      swap(data, mid, last)
    end

    return mid
  end

  local function partition(data, begin, end_, context, is_less)
    local pivot_idx = median_of_three(data, begin, end_, context, is_less)
    local pivot_value = data[pivot_idx]
    local right_idx = end_ - 1
    swap(data, pivot_idx, right_idx)

    local new_pivot_idx = begin
    for i = begin, right_idx - 1 do
      if not is_less(data[i], pivot_value, context) then
        swap(data, i, new_pivot_idx)
        new_pivot_idx = new_pivot_idx + 1
      end
    end
    swap(data, right_idx, new_pivot_idx)
  end

  local function qsort(data, begin, end_, context, is_less)
    if end_ - begin == 0 then return end
    local new_pivot = partition(data, begin, pivot, end_, context, is_less)
    qsort(data, begin, new_pivot, context, is_less)
    qsort(data, new_pivot+1, end_, context, is_less)
  end

  return qsort
end)()

return {
  qsort = qsort,
}
