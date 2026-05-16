module Main where

import Aweb.Config (parseConfig)
import Aweb.Service (runServer)

main :: IO ()
main = parseConfig >>= runServer
