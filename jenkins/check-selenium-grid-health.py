import urllib2
import json, sys, argparse
from pprint import pprint
from selenium import webdriver
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities


def checkSelenium(grid_url, site_url ):
    hub_url = grid_url+"/wd/hub"
    session_hub_url = grid_url+"/grid/api/testsession?session="

    driver_chrome = webdriver.Remote(hub_url, DesiredCapabilities.CHROME)
    driver_chrome.get(site_url)

    pprint(driver_chrome.title)

    sessionId = driver_chrome.session_id

    sessionInfo = urllib2.urlopen(session_hub_url+sessionId).read()

    sessionInfo = json.loads(sessionInfo)
    driver_chrome.close()

    pprint(sessionInfo)

    if (sessionInfo['success'] == True):
        return 0
    else:
        return 1
    
def main():
    parser = argparse.ArgumentParser(description='Check Selenium Grid')
    parser.add_argument('--grid_url', action='store',
                        help='Selenium Grid Hub url)', default=False, required=True)
    parser.add_argument('--site_url', action='store',
                        help='Site url for test', required=True)

    args = parser.parse_args()
    
    checkSelenium(grid_url=args.grid_url, site_url=args.site_url)

if __name__ == '__main__':
    main()