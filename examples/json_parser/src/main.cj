package json_parser

main(args: Array<String>): Int64 {
    if (args.isEmpty()) {
        println(parseJson(##"{"name":"CangjieCoder","ok":true,"items":[1,2,3]}"##).render())
        return 0
    }
    println(parseJson(args[0]).render())
    return 0
}
