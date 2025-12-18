import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/professor_service.dart';

class ProfessorsScreen extends StatefulWidget {
  const ProfessorsScreen({super.key});

  @override
  State<ProfessorsScreen> createState() => _ProfessorsScreenState();
}

class _ProfessorsScreenState extends State<ProfessorsScreen> {
  final ProfessorService _professorService = ProfessorService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadProfessors();
    
    // Listen to search changes
    _searchController.addListener(() {
      _professorService.searchProfessors(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProfessors() async {
    await _professorService.loadProfessors();
  }

  void _clearSearch() {
    _searchController.clear();
    _professorService.clearSearch();
    _searchFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Professor Directory'),
            Text(
              'Credits: Pratyush Nair',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (kIsWeb)
            IconButton(
              onPressed: _professorService.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }


  Widget _buildSearchBar() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Search Professors',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_professorService.professors.length} professors found',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search by professor name or chamber (e.g., "John" or "A101")',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) => setState(() {}),
                    onSubmitted: (value) => _searchFocusNode.unfocus(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showSortDialog,
                  icon: const Icon(Icons.sort),
                  label: const Text('Sort'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListenableBuilder(
      listenable: _professorService,
      builder: (context, _) {
        if (_professorService.isLoading) {
          return _buildLoadingView();
        }

        if (_professorService.error != null) {
          return _buildErrorView();
        }

        if (_professorService.professors.isEmpty) {
          return _buildEmptyView();
        }

        return _buildProfessorList();
      },
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading professors...',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading professors',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _professorService.error ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadProfessors,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    final hasSearch = _professorService.searchQuery.isNotEmpty;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.school_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch 
                ? 'No professors found'
                : 'No professors available',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch 
                ? 'Try searching with different keywords'
                : 'Professor data is not available yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          if (hasSearch) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear),
              label: const Text('Clear Search'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfessorList() {
    final professors = _professorService.professors;
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Professors',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${professors.length} results',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: professors.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildProfessorCard(professors[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessorCard(Professor professor) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            professor.name.isNotEmpty 
                ? professor.name[0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          professor.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          professor.chamber,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: professor.chamber == 'Unavailable'
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        trailing: professor.chamber != 'Unavailable'
            ? Icon(
                Icons.location_on,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort Professors'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                _professorService.sortType == ProfessorSortType.nameAsc
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _professorService.sortType == ProfessorSortType.nameAsc
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('Name (A-Z)'),
              onTap: () {
                _professorService.setSortType(ProfessorSortType.nameAsc);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                _professorService.sortType == ProfessorSortType.nameDesc
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _professorService.sortType == ProfessorSortType.nameDesc
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('Name (Z-A)'),
              onTap: () {
                _professorService.setSortType(ProfessorSortType.nameDesc);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                _professorService.sortType == ProfessorSortType.chamberAsc
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _professorService.sortType == ProfessorSortType.chamberAsc
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('Chamber (A-Z)'),
              onTap: () {
                _professorService.setSortType(ProfessorSortType.chamberAsc);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                _professorService.sortType == ProfessorSortType.chamberDesc
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _professorService.sortType == ProfessorSortType.chamberDesc
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: const Text('Chamber (Z-A)'),
              onTap: () {
                _professorService.setSortType(ProfessorSortType.chamberDesc);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

}