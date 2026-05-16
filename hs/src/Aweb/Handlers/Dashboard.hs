module Aweb.Handlers.Dashboard
  ( dashboardServer
  ) where

import Aweb.API (DashboardAPI)
import Servant

-- | Dashboard endpoint handler (stub implementation)
dashboardServer :: Server DashboardAPI
dashboardServer = throwError err501
