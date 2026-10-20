import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/auth_onboarding/domain/shop_profile.dart';
import 'package:siz/features/auth_onboarding/presentation/auth_providers.dart';
import 'package:siz/features/barbers/domain/barber.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  ConsumerState<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState
    extends ConsumerState<OnboardingWizardScreen> {
  int _currentStep = 0;

  // Step 1: Shop Details
  final _shopNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Step 2: Capacity
  int _totalChairs = 8;

  // Step 3: Initial Barbers Roster
  final List<Barber> _initialBarbers = [];
  final _barberNameCtrl = TextEditingController();
  final _barberPhoneCtrl = TextEditingController();
  final double _barberCommission = 0.60;

  // Step 4: Services Catalog
  final List<ServiceItem> _services = [
    const ServiceItem(
      id: '1',
      shopId: '',
      name: 'Standard Haircut',
      price: 25.0,
      durationMinutes: 30,
    ),
    const ServiceItem(
      id: '2',
      shopId: '',
      name: 'Beard Trim & Shape',
      price: 15.0,
      durationMinutes: 20,
    ),
    const ServiceItem(
      id: '3',
      shopId: '',
      name: 'Haircut + Beard Combo',
      price: 35.0,
      durationMinutes: 45,
    ),
    const ServiceItem(
      id: '4',
      shopId: '',
      name: 'Kids Haircut',
      price: 20.0,
      durationMinutes: 25,
    ),
  ];

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _barberNameCtrl.dispose();
    _barberPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barbershop Setup Wizard'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stepper(
          type: StepperType.horizontal,
          currentStep: _currentStep,
          onStepContinue: _onStepContinue,
          onStepCancel: _currentStep > 0
              ? () => setState(() => _currentStep -= 1)
              : null,
          controlsBuilder: (ctx, details) {
            final isLastStep = _currentStep == 3;
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: details.onStepCancel,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: authState.isLoading
                          ? null
                          : details.onStepContinue,
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(isLastStep ? 'Launch Shop Floor' : 'Continue'),
                    ),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Shop'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: _buildShopDetailsStep(),
            ),
            Step(
              title: const Text('Chairs'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: _buildCapacityStep(),
            ),
            Step(
              title: const Text('Barbers'),
              isActive: _currentStep >= 2,
              state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              content: _buildBarbersStep(),
            ),
            Step(
              title: const Text('Services'),
              isActive: _currentStep >= 3,
              state: _currentStep == 3 ? StepState.editing : StepState.indexed,
              content: _buildServicesStep(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tell us about your Barbershop',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _shopNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Barbershop Name *',
            hintText: 'e.g. Blade & Crown Barbershop',
            prefixIcon: Icon(Icons.storefront),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            labelText: 'Shop Address *',
            hintText: 'e.g. 104 Main Street, Downtown',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Business Phone Number *',
            hintText: '+1 555 019 2834',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildCapacityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How many barber chairs are in your shop?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your interactive floor plan will adapt dynamically to this number.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              Text(
                '$_totalChairs',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'Chairs / Stations',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Slider(
                value: _totalChairs.toDouble(),
                min: 2,
                max: 16,
                divisions: 14,
                label: '$_totalChairs Chairs',
                onChanged: (val) {
                  setState(() => _totalChairs = val.toInt());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarbersStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add your active barbers',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'You can assign them to chairs on the floor plan.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _barberNameCtrl,
                decoration: const InputDecoration(
                  labelText: "Barber's Name",
                  prefixIcon: Icon(Icons.person),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onPressed: () {
                final name = _barberNameCtrl.text.trim();
                if (name.isEmpty) return;
                setState(() {
                  _initialBarbers.add(
                    Barber(
                      id: const Uuid().v4(),
                      shopId: '',
                      name: name,
                      phone: _barberPhoneCtrl.text.trim(),
                      commissionRate: _barberCommission,
                      createdAt: DateTime.now(),
                    ),
                  );
                  _barberNameCtrl.clear();
                  _barberPhoneCtrl.clear();
                });
              },
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_initialBarbers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No barbers added yet. You can also add barbers later in the Barbers tab.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          )
        else
          ..._initialBarbers.asMap().entries.map((entry) {
            final idx = entry.key;
            final b = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: Colors.black,
                  child: Text(
                    b.name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  b.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Commission: ${(b.commissionRate * 100).toInt()}%',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () =>
                      setState(() => _initialBarbers.removeAt(idx)),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildServicesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Default Services & Pricing',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'Selectable at checkout. You can edit prices and add services later in Settings.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 14),
        ..._services.map((s) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.content_cut),
              title: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: Text(
                formatMoney(s.price),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_shopNameCtrl.text.trim().isEmpty ||
          _addressCtrl.text.trim().isEmpty ||
          _phoneCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all shop details.')),
        );
        return;
      }
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      // If no barbers entered, add at least one default barber
      if (_initialBarbers.isEmpty) {
        _initialBarbers.add(
          Barber(
            id: const Uuid().v4(),
            shopId: '',
            name: 'Master Barber',
            phone: _phoneCtrl.text.trim(),
            commissionRate: 0.60,
            createdAt: DateTime.now(),
          ),
        );
      }
      setState(() => _currentStep = 3);
    } else if (_currentStep == 3) {
      _finishSetup();
    }
  }

  Future<void> _finishSetup() async {
    final ok = await ref
        .read(authProvider.notifier)
        .completeOnboarding(
          name: _shopNameCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          totalChairs: _totalChairs,
          initialBarbers: _initialBarbers,
          services: _services,
        );
    if (!ok && mounted) {
      final message =
          ref.read(authProvider).errorMessage ?? 'Could not create the shop.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
