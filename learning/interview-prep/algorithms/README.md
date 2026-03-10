# 🧩 Алгоритмические задачи на Scala

> Решаем задачи в функциональном стиле — без var, без мутации, с pattern matching.

## Прогресс

| # | Задача | Сложность | Тема | Статус |
|---|--------|-----------|------|--------|
| 1 | Two Sum | Easy | Array, HashMap | ⬜ |
| 2 | Valid Parentheses | Easy | Stack | ⬜ |
| 3 | Merge Two Sorted Lists | Easy | LinkedList | ⬜ |
| 4 | Best Time to Buy/Sell Stock | Easy | Array, DP | ⬜ |
| 5 | Valid Palindrome | Easy | String, Two Pointers | ⬜ |
| 6 | Invert Binary Tree | Easy | Tree, Recursion | ⬜ |
| 7 | Maximum Subarray | Medium | Array, DP (Kadane) | ⬜ |
| 8 | 3Sum | Medium | Array, Two Pointers | ⬜ |
| 9 | Group Anagrams | Medium | HashMap, Sorting | ⬜ |
| 10 | Binary Tree Level Order | Medium | Tree, BFS | ⬜ |
| 11 | LRU Cache | Medium | HashMap, LinkedList | ⬜ |
| 12 | Course Schedule | Medium | Graph, Topological Sort | ⬜ |
| 13 | Word Search | Medium | Backtracking | ⬜ |
| 14 | Merge Intervals | Medium | Array, Sorting | ⬜ |
| 15 | Longest Palindromic Substring | Medium | DP, String | ⬜ |
| 16 | Median of Two Sorted Arrays | Hard | Binary Search | ⬜ |
| 17 | Trapping Rain Water | Hard | Array, Stack | ⬜ |
| 18 | Merge K Sorted Lists | Hard | Heap, LinkedList | ⬜ |
| 19 | Sliding Window Maximum | Hard | Deque | ⬜ |
| 20 | Word Ladder | Hard | BFS, Graph | ⬜ |

## Шаблон решения

```scala
// Файл: easy/001_two_sum.scala
// LeetCode #1: Two Sum
// https://leetcode.com/problems/two-sum/
// Сложность: O(n) time, O(n) space
// Тема: Array, HashMap

object TwoSum:
  // Функциональное решение через foldLeft
  def twoSum(nums: Array[Int], target: Int): Array[Int] =
    val result = nums.zipWithIndex.foldLeft(Map.empty[Int, Int]) { case (seen, (num, idx)) =>
      val complement = target - num
      if seen.contains(complement) then return Array(seen(complement), idx)
      seen + (num -> idx)
    }
    Array.empty // не найдено

  // Тесты
  @main def test(): Unit =
    assert(twoSum(Array(2, 7, 11, 15), 9).toSeq == Seq(0, 1))
    assert(twoSum(Array(3, 2, 4), 6).toSeq == Seq(1, 2))
    println("✅ All tests passed")
```

## Правила

1. **Решать на Scala 3** — идиоматично, без var
2. **Сначала brute force**, потом оптимизация
3. **Писать сложность** — O(time) и O(space)
4. **Минимум 3 теста** на каждую задачу
5. **Коммитить каждое решение** — git log = прогресс

---

*Обновлён по мере решения задач*
