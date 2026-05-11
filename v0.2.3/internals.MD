## Translation ruleset and priority

PerfTest.jl translates a declarative recipe file for performance tests into a Julia expression that can actually execute them. The traslation prodedure is done by walking through the recipe code whilst trying to do pattern matching with a set of translation rules. The translation rules are totally ordered, which means that there is a clear hierarchy on which pattern is translated in case an expression fits two patterns at the same time. Below there is a full list of the rules, in decreasing order by priority. Given the way the macros in the package are declared there should not be ambiguous pattern matching but for further safety the priority is enforced.

  1. @testset macro
  2. @test macro
  3. @test_throws macro
  4. @test_logs macro
  5. @inferred macro
  6. @test_deprecated macro
  7. @test_warn macro
  8. @test_nowarn macro
  9. @test_broken macro
  10. @test_skip macro
  11. @perftest macro
  12. Back context token, internal use only
  13. Prefix placement token, internal use only
  14. Suffix placement token, internal use only
  15. @config macro
  16. @on\_perftest\_exec macro
  17. @on\_perftest\_ignore macro
  18. @define\_eff\_memory\_throughput macro
  19. @define\_metric macro
  20. @define\_benchmark macro
  21.  @roofline macro
  22. @auxiliary\_metric macro 
  23. @perfcompare macro
  24. Recursivity rule, used for includes inside testsets

Inside a @perftest macro the expression has to be manipulated to be able tu use local variables in a global context (a requirement of `BenchmarkTools.jl`). The rules have the following priority:

  1. Assignment pattern rule:  a = b
  2. Function argument pattern rule:  f(arg)
  3. Vectorized function call pattern rule: f.(arg)
  4. Dot operator pattern rule: a.b