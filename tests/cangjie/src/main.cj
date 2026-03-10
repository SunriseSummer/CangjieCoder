package testproject

func greet(name: String): String {
    return "Hello, ${name}!"
}

main() {
    let message = greet("World")
    println(message)
    println("Sum: ${add(3, 4)}")
}
