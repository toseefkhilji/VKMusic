//
//  FriendsTableViewController.swift
//  VkPlaylist
//
//  MIT License
//
//  Copyright (c) 2016 Ilya Khalyapin
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import UIKit

/// Контроллер содержит таблицу со списком друзей
class FriendsTableViewController: UITableViewController {
    
    /// Выполняется ли обновление
    var isRefreshing: Bool {
        if let refreshControl = refreshControl where refreshControl.refreshing {
            return true
        } else {
            return false
        }
    }
    
    /// Статус выполнения запроса к серверу
    var requestManagerStatus: RequestManagerObject.State {
        return RequestManager.sharedInstance.getFriends.state
    }
    /// Ошибки при выполнении запроса к серверу
    var requestManagerError: RequestManagerObject.ErrorRequest {
        return RequestManager.sharedInstance.getFriends.error
    }
    
    /// Кэш аватарок друзей
    private var imageCache = NSCache()
    
    /// Словарь с именами [Первая буква фамилии : Массив друзей, у которых фамилия начинается на ту же букву]
    private var names = [String: [Friend]]()
    /// Массив содержащий заголовки секций таблицы (первые буквы фамилий)
    private var nameSectionTitles = [String]()
    
    /// Массив друзей, загруженных с сервера
    private var friends = [Friend]()
    /// Массив друзей, полученный в результате поиска
    private var filteredFriends = [Friend]()
    
    /// Массив друзей, отображаемый на экране
    var activeArray: [Friend] {
        if isSearched {
            return filteredFriends
        } else {
            return friends
        }
    }
    
    /// Поисковый контроллер
    let searchController = UISearchController(searchResultsController: nil)
    /// Выполняется ли сейчас поиск
    var isSearched: Bool {
        return searchController.active && !searchController.searchBar.text!.isEmpty
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if VKAPIManager.isAuthorized {
            getFriends()
        }
        
        // Настройка Pull-To-Refresh
        pullToRefreshEnable(VKAPIManager.isAuthorized)
        
        // Настройка поисковой панели
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        
        searchController.dimsBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.searchBarStyle = .Prominent
        searchController.searchBar.placeholder = "Поиск"
        definesPresentationContext = true
        
        searchEnable(VKAPIManager.isAuthorized)
        
        // Кастомизация tableView
        tableView.tableFooterView = UIView() // Чистим пустое пространство под таблицей
        
        // Регистрация ячеек
        var cellNib = UINib(nibName: TableViewCellIdentifiers.noAuthorizedCell, bundle: nil) // Ячейка "Необходимо авторизоваться"
        tableView.registerNib(cellNib, forCellReuseIdentifier: TableViewCellIdentifiers.noAuthorizedCell)
        
        cellNib = UINib(nibName: TableViewCellIdentifiers.networkErrorCell, bundle: nil) // Ячейка "Ошибка при подключении к интернету"
        tableView.registerNib(cellNib, forCellReuseIdentifier: TableViewCellIdentifiers.networkErrorCell)
        
        cellNib = UINib(nibName: TableViewCellIdentifiers.nothingFoundCell, bundle: nil) // Ячейка "Ничего не найдено"
        tableView.registerNib(cellNib, forCellReuseIdentifier: TableViewCellIdentifiers.nothingFoundCell)
        
        cellNib = UINib(nibName: TableViewCellIdentifiers.loadingCell, bundle: nil) // Ячейка "Загрузка"
        tableView.registerNib(cellNib, forCellReuseIdentifier: TableViewCellIdentifiers.loadingCell)
        
        cellNib = UINib(nibName: TableViewCellIdentifiers.numberOfRowsCell, bundle: nil) // Ячейка с количеством друзей
        tableView.registerNib(cellNib, forCellReuseIdentifier: TableViewCellIdentifiers.numberOfRowsCell)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        if let _ = tableView.tableHeaderView {
            if tableView.contentOffset.y == 0 {
                tableView.hideSearchBar()
            }
        }
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == SegueIdentifiers.showFriendAudioViewControllerSegue {
            let ownerMusicViewController = segue.destinationViewController as! OwnerMusicViewController
            let friend = sender as! Friend
            
            ownerMusicViewController.id = friend.id
            ownerMusicViewController.name = friend.getFullName()
        }
    }
    
    deinit {
        if let superView = searchController.view.superview {
            superView.removeFromSuperview()
        }
    }
    
    /// Заново отрисовать таблицу
    func reloadTableView() {
        dispatch_async(dispatch_get_main_queue()) {
            self.tableView.reloadData()
        }
    }
    
    
    // MARK: Pull-to-Refresh
    
    /// Управление доступностью Pull-to-Refresh
    func pullToRefreshEnable(enable: Bool) {
        if enable {
            if refreshControl == nil {
                refreshControl = UIRefreshControl()
                //refreshControl!.attributedTitle = NSAttributedString(string: "Потяните, чтобы обновить...") // Все крашится :с
                refreshControl!.addTarget(self, action: #selector(getFriends), forControlEvents: .ValueChanged) // Добавляем обработчик контроллера обновления
            }
        } else {
            if let refreshControl = refreshControl {
                if refreshControl.refreshing {
                    refreshControl.endRefreshing()
                }
                
                refreshControl.removeTarget(self, action: #selector(getFriends), forControlEvents: .ValueChanged) // Удаляем обработчик контроллера обновления
            }
            
            refreshControl = nil
        }
    }
    
    
    // MARK: Работа с клавиатурой
    
    /// Распознаватель тапов по экрану
    lazy var tapRecognizer: UITapGestureRecognizer = {
        var recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        return recognizer
    }()
    
    /// Спрятать клавиатуру у поисковой строки
    func dismissKeyboard() {
        searchController.searchBar.resignFirstResponder()
        
        if searchController.active && searchController.searchBar.text!.isEmpty {
            searchController.active = false
        }
    }
    
    
    // MARK: Выполнение запроса на получение списка друзей
    
    /// Запрос на получение списка друзей с сервера
    func getFriends() {
        RequestManager.sharedInstance.getFriends.performRequest() { success in
            self.friends = DataManager.sharedInstance.friends.array
            
            self.names = [:]
            self.nameSectionTitles = []
            
            // Распределяем по секциям
            if self.requestManagerStatus == .Results {
                for friend in self.friends {
                    
                    // Устанавливаем по какому значению будем сортировать
                    let name = friend.last_name
                    
                    var firstCharacter = String(name.characters.first!)
                    
                    let characterSet = NSCharacterSet(charactersInString: "абвгдеёжзийклмнопрстуфхцчшщъыьэюя" + "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ" + "abcdefghijklmnopqrstuvwxyz" + "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                    if (NSString(string: firstCharacter).rangeOfCharacterFromSet(characterSet.invertedSet).location != NSNotFound){
                        firstCharacter = "#"
                    }
                    
                    if self.names[String(firstCharacter)] == nil {
                        self.names[String(firstCharacter)] = []
                    }
                    
                    self.names[String(firstCharacter)]!.append(friend)
                }
                
                self.nameSectionTitles = self.names.keys.sort { (left: String, right: String) -> Bool in
                    return left.localizedStandardCompare(right) == .OrderedAscending // Сортировка по возрастанию
                }
                
                if self.nameSectionTitles.first == "#" {
                    self.nameSectionTitles.removeFirst()
                    self.nameSectionTitles.append("#")
                }
                
                // Сортируем имена в каждой секции
                for (key, section) in self.names {
                    self.names[key] = section.sort { (left: Friend, right: Friend) -> Bool in
                        let leftFullName = left.last_name + " " + left.first_name
                        let rightFullName = right.last_name + " " + right.first_name
                        
                        return leftFullName.localizedStandardCompare(rightFullName) == .OrderedAscending // Сортировка по возрастанию
                    }
                }
            }
            
            self.reloadTableView()
            
            if self.isRefreshing { // Если данные обновляются
                self.refreshControl!.endRefreshing() // Говорим что обновление завершено
            }
            
            if !success {
                switch self.requestManagerError {
                case .UnknownError:
                    let alertController = UIAlertController(title: "Ошибка", message: "Произошла какая-то ошибка, попробуйте еще раз...", preferredStyle: .Alert)
                    
                    let okAction = UIAlertAction(title: "ОК", style: .Default, handler: nil)
                    alertController.addAction(okAction)
                    
                    dispatch_async(dispatch_get_main_queue()) {
                        self.presentViewController(alertController, animated: false, completion: nil)
                    }
                default:
                    break
                }
            }
        }
    }
    
    
    // MARK: Поиск
    
    /// Управление доступностью поиска
    func searchEnable(enable: Bool) {
        if enable {
            if tableView.tableHeaderView == nil {
                searchController.searchBar.alpha = 1
                tableView.tableHeaderView = searchController.searchBar
                tableView.hideSearchBar()
            }
        } else {
            if let _ = tableView.tableHeaderView {
                searchController.searchBar.alpha = 0
                searchController.active = false
                tableView.tableHeaderView = nil
                tableView.contentOffset = CGPointZero
            }
        }
    }
    
    /// Выполнение поискового запроса
    func filterContentForSearchText(searchText: String) {
        filteredFriends = friends.filter { friend in
            return friend.first_name.lowercaseString.containsString(searchText.lowercaseString) || friend.last_name.lowercaseString.containsString(searchText.lowercaseString)
        }
    }
    
    
    // MARK: Получение ячеек для строк таблицы helpers
    
    /// Текст для ячейки с сообщением о том, что сервер вернул пустой массив
    var noResultsLabelText: String {
        return "Список друзей пуст"
    }
    
    /// Текст для ячейки с сообщением о том, что при поиске ничего не найдено
    var nothingFoundLabelText: String {
        return "Измените поисковый запрос"
    }
    
    // Получение количества друзей в списке для ячейки с количеством друзей
    func numberOfFriendsForIndexPath(indexPath: NSIndexPath) -> Int? {
        let sectionTitle = nameSectionTitles[indexPath.section]
        let sectionNames = names[sectionTitle]
        
        let count: Int?
        
        if isSearched && filteredFriends.count == indexPath.row {
            count = filteredFriends.count
        } else if !isSearched && sectionNames!.count == indexPath.row {
            count = friends.count
        } else {
            count = nil
        }
        
        return count
    }
    
    /// Текст для ячейки с сообщением о необходимости авторизоваться
    var noAuthorizedLabelText: String {
        return "Необходимо авторизоваться"
    }
    
    
    // MARK: Получение ячеек для строк таблицы
    
    // Ячейка для строки когда поиск еще не выполнялся и была получена ошибка при подключении к интернету
    func getCellForNotSearchedYetRowWithInternetErrorForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.networkErrorCell, forIndexPath: indexPath) as! NetworkErrorCell
        
        return cell
    }
    
    // Ячейка для строки когда поиск еще не выполнялся
    func getCellForNotSearchedYetRowForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        return UITableViewCell()
    }
    
    // Ячейка для строки с сообщением что сервер вернул пустой массив
    func getCellForNoResultsRowForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.nothingFoundCell, forIndexPath: indexPath) as! NothingFoundCell
        cell.messageLabel.text = noResultsLabelText
        
        return cell
    }
    
    // Ячейка для строки с сообщением, что при поиске ничего не было найдено
    func getCellForNothingFoundRowForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        let nothingFoundCell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.nothingFoundCell, forIndexPath: indexPath) as! NothingFoundCell
        nothingFoundCell.messageLabel.text = nothingFoundLabelText
        
        return nothingFoundCell
    }
    
    // Ячейка для строки с сообщением о загрузке
    func getCellForLoadingRowForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.loadingCell, forIndexPath: indexPath) as! LoadingCell
        cell.activityIndicator.startAnimating()
        
        return cell
    }
    
    // Пытаемся получить ячейку для строки с количеством друзей
    func getCellForNumberOfFriendsRowForIndexPath(indexPath: NSIndexPath) -> UITableViewCell? {
        let count = numberOfFriendsForIndexPath(indexPath)
        
        if let count = count {
            let numberOfRowsCell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.numberOfRowsCell) as! NumberOfRowsCell
            numberOfRowsCell.configureForType(.Friend, withCount: count)
            
            return numberOfRowsCell
        }
        
        return nil
    }
    
    // Ячейка для строки с другом
    func getCellForRowWithGroupForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        let sectionTitle = nameSectionTitles[indexPath.section]
        let sectionNames = names[sectionTitle]
        
        let friend = isSearched ? filteredFriends[indexPath.row] : sectionNames![indexPath.row]
        
        let cell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.friendCell, forIndexPath: indexPath) as! FriendCell
        cell.configureForFriend(friend, withImageCacheStorage: imageCache)
        
        return cell
    }
    
    // Ячейка для строки с сообщением о необходимости авторизоваться
    func getCellForNoAuthorizedRowForIndexPath(indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(TableViewCellIdentifiers.noAuthorizedCell, forIndexPath: indexPath) as! NoAuthorizedCell
        cell.messageLabel.text = noAuthorizedLabelText
        
        return cell
    }

}


// MARK: UITableViewDataSource

private typealias _FriendsTableViewControllerDataSource = FriendsTableViewController
extension _FriendsTableViewControllerDataSource {
    
    // Получение количество секций
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if VKAPIManager.isAuthorized {
            switch requestManagerStatus {
            case .Loading where isRefreshing:
                return nameSectionTitles.count
            case .Results:
                return isSearched ? 1 : nameSectionTitles.count
            default:
                return 1
            }
        }
        
        return 1
    }
    
    // Получение заголовков секций
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if VKAPIManager.isAuthorized {
            switch requestManagerStatus {
            case .Loading where isRefreshing:
                return nameSectionTitles[section]
            case .Results:
                return isSearched ? nil : nameSectionTitles[section]
            default:
                return nil
            }
        }
        
        return nil
    }
    
    // Получение количества строк таблицы в указанной секции
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if VKAPIManager.isAuthorized {
            switch requestManagerStatus {
            case .NotSearchedYet where requestManagerError == .NetworkError:
                return 1 // Ячейка с сообщением об отсутствии интернет соединения
            case .Loading where isRefreshing:
                let sectionTitle = nameSectionTitles[section]
                let sectionNames = names[sectionTitle]
                
                var count = sectionNames!.count
                
                if nameSectionTitles.count - 1 == section {
                    count += 1 // Для ячейки с количеством друзей в последней секции
                }
                
                return count
            case .Loading:
                return 1 // Ячейка с индикатором загрузки
            case .NoResults:
                return 1 // Ячейки с сообщением об отсутствии друзей
            case .Results:
                if isSearched {
                    return filteredFriends.count == 0 ? 1 : filteredFriends.count + 1 // Если массив пустой - ячейка с сообщением об отсутствии результатов поиска, иначе - количество найденных друзей
                } else {
                    let sectionTitle = nameSectionTitles[section]
                    let sectionNames = names[sectionTitle]
                    
                    var count = sectionNames!.count
                    
                    if nameSectionTitles.count - 1 == section {
                        count += 1 // Для ячейки с количеством друзей в последней секции
                    }
                    
                    return count
                }
            default:
                return 0
            }
        }
        
        return 1 // Ячейка с сообщением о необходимости авторизоваться
    }
    
    // Получение ячейки для строки таблицы
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if VKAPIManager.isAuthorized {
            switch requestManagerStatus {
            case .NotSearchedYet where requestManagerError == .NetworkError:
               return getCellForNotSearchedYetRowWithInternetErrorForIndexPath(indexPath)
            case .NotSearchedYet:
                return getCellForNotSearchedYetRowForIndexPath(indexPath)
            case .NoResults:
                return getCellForNoResultsRowForIndexPath(indexPath)
            case .Loading where isRefreshing:
                if let numberOfRowsCell = getCellForNumberOfFriendsRowForIndexPath(indexPath) {
                    return numberOfRowsCell
                }
                
                return getCellForRowWithGroupForIndexPath(indexPath)
            case .Loading:
                return getCellForLoadingRowForIndexPath(indexPath)
            case .Results:
                if searchController.active && searchController.searchBar.text != "" && filteredFriends.count == 0 {
                    return getCellForNothingFoundRowForIndexPath(indexPath)
                }
                
                if let numberOfRowsCell = getCellForNumberOfFriendsRowForIndexPath(indexPath) {
                    return numberOfRowsCell
                }
                
                return getCellForRowWithGroupForIndexPath(indexPath)
            }
        }
        
        return getCellForNoAuthorizedRowForIndexPath(indexPath)
    }
    
    // Получение массива индексов секций таблицы
    override func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        if VKAPIManager.isAuthorized {
            switch requestManagerStatus {
            case .Loading where isRefreshing:
                return nameSectionTitles
            case .Results:
                return isSearched ? nil : nameSectionTitles
            default:
                return nil
            }
        }
        
        return nil
    }
    
}


// MARK: UITableViewDelegate

private typealias _FriendsTableViewControllerDelegate = FriendsTableViewController
extension _FriendsTableViewControllerDelegate {
    
    // Высота каждой строки
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        if VKAPIManager.isAuthorized {
            if requestManagerStatus == .Results || requestManagerStatus == .Loading && isRefreshing {
                let sectionTitle = nameSectionTitles[indexPath.section]
                let sectionNames = names[sectionTitle]
                
                let count: Int?
                
                if searchController.active && searchController.searchBar.text != "" && filteredFriends.count == indexPath.row && filteredFriends.count != 0 {
                    count = filteredFriends.count
                } else if sectionNames!.count == indexPath.row {
                    count = sectionNames!.count
                } else {
                    count = nil
                }
                
                if let _ = count {
                    return 44
                }
            }
        }
        
        return 62
    }
    
    // Вызывается при тапе по строке таблицы
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        
        if tableView.cellForRowAtIndexPath(indexPath) is FriendCell {
            var friend: Friend
                
            if isSearched {
                friend = filteredFriends[indexPath.row]
            } else {
                let sectionTitle = nameSectionTitles[indexPath.section]
                let sectionNames = names[sectionTitle]
                
                friend = sectionNames![indexPath.row]
            }
            
            performSegueWithIdentifier(SegueIdentifiers.showFriendAudioViewControllerSegue, sender: friend)
        }
    }
    
}


// MARK: UISearchBarDelegate

extension FriendsTableViewController: UISearchBarDelegate {
    
    // Пользователь хочет начать поиск
    func searchBarShouldBeginEditing(searchBar: UISearchBar) -> Bool {
        if VKAPIManager.isAuthorized {
            switch requestManagerStatus {
            case .Results:
                if let refreshControl = refreshControl {
                    return !refreshControl.refreshing
                }
                
                return friends.count != 0
            default:
                return false
            }
        } else {
            return false
        }
    }
    
    // Пользователь начал редактирование поискового текста
    func searchBarTextDidBeginEditing(searchBar: UISearchBar) {
        view.addGestureRecognizer(tapRecognizer)
        
        pullToRefreshEnable(false)
    }
    
    // Пользователь закончил редактирование поискового текста
    func searchBarTextDidEndEditing(searchBar: UISearchBar) {
        view.removeGestureRecognizer(tapRecognizer)
        
        pullToRefreshEnable(true)
    }
    
    // В поисковой панели была нажата кнопка "Отмена"
    func searchBarCancelButtonClicked(searchBar: UISearchBar) {
        filteredFriends.removeAll()
    }
    
}


// MARK: UISearchResultsUpdating

extension FriendsTableViewController: UISearchResultsUpdating {
    
    // Поле поиска получило фокус или значение поискового запроса изменилось
    func updateSearchResultsForSearchController(searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
        reloadTableView()
    }
    
}