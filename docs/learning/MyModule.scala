object MyModule {
  private def fib(n: Int): Int = {
    @annotation.tailrec
    def fibHelper(n: Int, acc: Int, prev: Int): Int =
      if (n == 0) acc
      else fibHelper(n - 1, prev, acc + prev)
    fibHelper(n, 0, 1)
  }

  def factorial(n: Int): Int = {
    @annotation.tailrec
    def go(n: Int, acc: Int): Int =
    if (n <= 0) acc
    else go(n-1, n*acc)
    go(n, 1)
  }

  private def abs(n: Int): Int = if (n < 0) -n else n

  private def formatAbs(x: Int) = {
    val msg = "The absolute value of %d is %d."
    msg.format(x, abs(x))       
  }

  private def formatFactorial(n: Int) = {
    val msg = "The factorial of %d is %d."
    msg.format(n, factorial(n))
  }

  private def formatFibo(n: Int) = {
    val msg = "The fibonacci of %d is %d."
    msg.format(n, fib(n))
  }

  def isSorted[A](as: Array[A], ordered: (A, A) => Boolean): Boolean = {
    @annotation.tailrec
    def go(n: Int): Boolean =
      if (n >= as.length - 1) true
      else if (!ordered(as(n), as(n + 1))) false
      else go(n + 1)
    go(0)
  }

  def curry[A,B,C](f: (A, B) => C): A => (B => C) =
    a => b => f(a, b)
  def uncurry[A,B,C](f: A => B => C): (A, B) => C = 
    (a, b) => f(a)(b)
  def compose[A,B,C](f: B => C, g: A => B): A => C  = a => g(a) andThen f

  def main(args: Array[String]): Unit = {
    println(formatAbs(-42))
    println(formatFactorial(7))
    println(formatFibo(10))
  }  
}
